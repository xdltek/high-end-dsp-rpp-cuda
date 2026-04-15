/**
 * @file rpp_fft_perf_boost.cpp
 * @brief Compare baseline FFT mode and optimized FFT mode. See rpp_fft_perf_boost/README.md for full workflow.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include <sys/time.h>

#include "rpp_drv_api.h"
#include <rppfft.h>
#include <rpp_runtime.h>
#include <rpp_smgr.h>

struct PerfCaseConfig
{
    const char* name;
    int batch;
    int fft_size;
    int warmup_iters;
    int measure_iters;
    bool column_fft;
    bool fast_algo;
    bool runtime_io;
};

/**
 * @brief Get current wall-clock timestamp in microseconds.
 * @return Current time in microseconds.
 */
static inline unsigned long long now_us()
{
    struct timeval tv;
    struct timezone tz;
    gettimeofday(&tv, &tz);
    return (unsigned long long)tv.tv_sec * 1000000ULL + (unsigned long long)tv.tv_usec;
}

/**
 * @brief Generate deterministic complex input for FFT benchmarking.
 * @param input Output input buffer.
 * @param batch Batch count.
 * @param fft_size FFT length.
 * @param column_fft Whether to fill using column-major addressing.
 */
static void generate_input(rppfftComplex* input, int batch, int fft_size, bool column_fft)
{
    int cnt = 0;
    for (int b = 0; b < batch; b++)
    {
        for (int k = 0; k < fft_size; k++)
        {
            int idx = column_fft ? (k * batch + b) : (b * fft_size + k);
            input[idx].x = (float)(cnt++);
            input[idx].y = 0.0f;
        }
    }
}

/**
 * @brief Print a small output slice for quick sanity check.
 * @param tag Section tag.
 * @param out FFT output buffer.
 * @param total_count Total number of complex points.
 */
static void print_first_outputs(const char* tag, const rppfftComplex* out, int total_count)
{
    int print_n = total_count < 16 ? total_count : 16;
    printf("%s first %d output values:\n", tag, print_n);
    for (int i = 0; i < print_n; i++)
    {
        printf("[%02d] (%10.4f, %10.4f)%s", i, out[i].x, out[i].y, ((i + 1) % 2 == 0) ? "\n" : "  ");
    }
    if (print_n % 2 != 0) printf("\n");
}

/**
 * @brief Run one FFT performance case and return average device time.
 * @param cfg Case configuration (shape, mode, iterations).
 * @return Average device execution time in microseconds per iteration.
 */
static double run_perf_case(const PerfCaseConfig& cfg)
{
    printf("\n============================================================\n");
    printf("[CASE] %s\n", cfg.name);
    printf("batch=%d, fft_size=%d, columnFft=%d, fastAlgo=%d, runtimeIo=%d\n",
           cfg.batch, cfg.fft_size, (int)cfg.column_fft, (int)cfg.fast_algo, (int)cfg.runtime_io);
    printf("============================================================\n");

    const int count = cfg.batch * cfg.fft_size;
    const size_t bytes = (size_t)count * sizeof(rppfftComplex);

    rppfftComplex* host_in = nullptr;
    rppfftComplex* host_out = nullptr;
    rppfftComplex* device_in = nullptr;
    rppfftComplex* device_out = nullptr;
    rtStream_t stream = nullptr;
    rppfftHandle plan = {};
    rppfftResult ret;
    rppsmgr::SRamManager& smgr = rppsmgr::SRamManager::GetInstance();

    assert(rtSuccess == rtMallocHost((void**)&host_in, bytes));
    assert(rtSuccess == rtMallocHost((void**)&host_out, bytes));
    assert(rtSuccess == rtMalloc((void**)&device_in, bytes));
    assert(rtSuccess == rtMalloc((void**)&device_out, bytes));

    generate_input(host_in, cfg.batch, cfg.fft_size, cfg.column_fft);
    // rtMemcpy: copy host input to device DDR.
    assert(rtSuccess == rtMemcpy(device_in, host_in, bytes, rtMemcpyHostToDevice));

    if (cfg.fast_algo)
    {
        // Fast path requires SRAM capacity limit.
        assert(cfg.batch * cfg.fft_size <= FAST_FFT_SIZE);
        // Map DDR buffers to SRAM and prepare FFT-friendly format.
        // SRamManager Allocate/Download/Reformat: prepare SRAM fast path input/output.
        smgr.Allocate(device_in, cfg.batch, cfg.fft_size, sizeof(rppfftComplex), HCFMT);
        smgr.Allocate(device_out, cfg.batch, cfg.fft_size, sizeof(rppfftComplex), RCFMT);
        smgr.Download(device_in);
        smgr.ReformatInPlace(device_in);
    }

    if (cfg.runtime_io)
    {
        // rppfftPlan1d: build plan in runtime-I/O mode.
        ret = rppfftPlan1d(&plan,
                           cfg.fft_size,
                           RPPFFT_C2C,
                           cfg.batch,
                           false,
                           cfg.column_fft,
                           cfg.fast_algo);
    }
    else
    {
        // Fixed I/O mode binds input/output buffer addresses into the plan.
        // rppfftPlan1d: build plan with fixed input/output buffer binding.
        ret = rppfftPlan1d(&plan,
                           cfg.fft_size,
                           RPPFFT_C2C,
                           cfg.batch,
                           false,
                           cfg.column_fft,
                           cfg.fast_algo,
                           device_in,
                           device_out,
                           RPPFFT_FORWARD);
    }
    assert(ret == RPPFFT_SUCCESS);

    // rtStreamCreate + rppfftSetStream: bind FFT execution to one stream.
    assert(rtSuccess == rtStreamCreate(&stream));
    rppfftSetStream(plan, stream);

    for (int i = 0; i < cfg.warmup_iters; i++)
    {
        // rppfftExecC2C: enqueue FFT execution.
        rppfftExecC2C(plan, device_in, device_out, RPPFFT_FORWARD);
    }
    assert(rtSuccess == rtStreamSynchronize(stream));

    unsigned long long t0 = now_us();
    for (int i = 0; i < cfg.measure_iters; i++)
    {
        rppfftExecC2C(plan, device_in, device_out, RPPFFT_FORWARD);
    }
    assert(rtSuccess == rtStreamSynchronize(stream));
    unsigned long long t1 = now_us();

    if (cfg.fast_algo)
    {
        // Convert SRAM output back and upload to DDR for host-side visibility.
        // SRamManager Upload path: SRAM -> device DDR.
        smgr.ReformatInPlace(device_out);
        smgr.Upload(device_out);
    }
    // rtMemcpy: copy device DDR output back to host for reporting.
    assert(rtSuccess == rtMemcpy(host_out, device_out, bytes, rtMemcpyDeviceToHost));

    double avg_us = (double)(t1 - t0) / (double)cfg.measure_iters;
    printf("Average device time: %.3f us / iter (%d iterations)\n", avg_us, cfg.measure_iters);
    print_first_outputs("[OUTPUT]", host_out, count);

    if (cfg.fast_algo)
    {
        smgr.Free(device_in);
        smgr.Free(device_out);
        smgr.Clear();
    }

    rppfftDestroy(plan);
    rtStreamDestroy(stream);
    rtFree(device_in);
    rtFree(device_out);
    rtFreeHost(host_in);
    rtFreeHost(host_out);
    return avg_us;
}

/**
 * @brief Demo entry point: compare baseline mode and optimized mode and report speedup.
 * @return 0 on success.
 */
int main()
{
    rppsmgr::SRamManager& smgr = rppsmgr::SRamManager::GetInstance();
    // SRamManager Init: allocate workspace used by fast FFT mode.
    smgr.Init(SRAM_WORK_SPACE);

    PerfCaseConfig baseline = {
        "Baseline: normal mode + columnFft=false + runtime I/O",
        1024, 256, 20, 200, false, false, true
    };

    PerfCaseConfig optimized = {
        "Optimized: fast mode + columnFft=true + fixed I/O",
        1024, 256, 20, 200, true, true, false
    };

    double baseline_us = run_perf_case(baseline);
    double optimized_us = run_perf_case(optimized);

    printf("\n===================== PERFORMANCE SUMMARY ===================\n");
    printf("Baseline  avg: %10.3f us\n", baseline_us);
    printf("Optimized avg: %10.3f us\n", optimized_us);
    if (optimized_us > 0.0)
    {
        printf("Speedup (baseline/optimized): %.3fx\n", baseline_us / optimized_us);
    }
    printf("============================================================\n");

    // SRamManager Destroy: release workspace before process exit.
    smgr.Destroy();
    return 0;
}
