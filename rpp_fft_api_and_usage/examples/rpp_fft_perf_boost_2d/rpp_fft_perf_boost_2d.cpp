/**
 * @file rpp_fft_perf_boost_2d.cpp
 * @brief 2D FFT performance comparison demo for baseline vs optimized modes. See rpp_fft_perf_boost_2d/README.md for full workflow.
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

struct Perf2DCaseConfig
{
    const char* name;
    int height;
    int width;
    int warmup_iters;
    int measure_iters;
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
 * @brief Generate deterministic 2D complex input for FFT benchmarking.
 * @param input Output input buffer.
 * @param height Matrix height.
 * @param width Matrix width.
 */
static void generate_input_2d(rppfftComplex* input, int height, int width)
{
    int cnt = 0;
    for (int h = 0; h < height; h++)
    {
        for (int w = 0; w < width; w++)
        {
            int idx = h * width + w;
            input[idx].x = (float)(cnt++);
            input[idx].y = 0.0f;
        }
    }
}

/**
 * @brief Print a small output slice for quick correctness inspection.
 * @param tag Section label.
 * @param out Output buffer.
 * @param total_count Total number of complex elements.
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
 * @brief Run one 2D FFT performance case and return average device time.
 * @param cfg Case configuration (shape, mode, and iteration counts).
 * @return Average device execution time in microseconds per iteration.
 */
static double run_perf_case_2d(const Perf2DCaseConfig& cfg)
{
    printf("\n============================================================\n");
    printf("[CASE] %s\n", cfg.name);
    printf("height=%d, width=%d, fastAlgo=%d, runtimeIo=%d\n",
           cfg.height, cfg.width, (int)cfg.fast_algo, (int)cfg.runtime_io);
    printf("============================================================\n");

    const int count = cfg.height * cfg.width;
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

    generate_input_2d(host_in, cfg.height, cfg.width);
    // rtMemcpy: copy host input matrix to device DDR.
    assert(rtSuccess == rtMemcpy(device_in, host_in, bytes, rtMemcpyHostToDevice));

    if (cfg.fast_algo)
    {
        // Fast path requires SRAM capacity limit.
        assert(cfg.height * cfg.width <= FAST_FFT_SIZE);
        // SRamManager: map DDR buffers to SRAM and prepare FFT-friendly format.
        smgr.Allocate(device_in, cfg.height, cfg.width, sizeof(rppfftComplex), HCFMT);
        smgr.Allocate(device_out, cfg.height, cfg.width, sizeof(rppfftComplex), RCFMT);
        smgr.Download(device_in);
        smgr.ReformatInPlace(device_in);
    }

    if (cfg.runtime_io)
    {
        // rppfftPlan2d: build plan in runtime I/O mode.
        ret = rppfftPlan2d(&plan,
                           cfg.height,
                           cfg.width,
                           RPPFFT_C2C,
                           cfg.fast_algo);
    }
    else
    {
        // Fixed I/O mode binds input/output buffer addresses into the plan.
        // rppfftPlan2d: build plan in fixed I/O mode.
        ret = rppfftPlan2d(&plan,
                           cfg.height,
                           cfg.width,
                           RPPFFT_C2C,
                           cfg.fast_algo,
                           device_in,
                           device_out,
                           RPPFFT_FORWARD);
    }
    assert(ret == RPPFFT_SUCCESS);

    // rtStreamCreate + rppfftSetStream: bind FFT execution to this stream.
    assert(rtSuccess == rtStreamCreate(&stream));
    rppfftSetStream(plan, stream);

    for (int i = 0; i < cfg.warmup_iters; i++)
    {
        // rppfftExecC2C: enqueue one FFT execution.
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
        // SRamManager: convert fast-path SRAM output and upload to device DDR.
        smgr.ReformatInPlace(device_out);
        smgr.Upload(device_out);
    }
    // rtMemcpy: copy device DDR output back to host.
    assert(rtSuccess == rtMemcpy(host_out, device_out, bytes, rtMemcpyDeviceToHost));

    double avg_us = (double)(t1 - t0) / (double)cfg.measure_iters;
    printf("Average device time: %.3f us / iter (%d iterations)\n", avg_us, cfg.measure_iters);
    print_first_outputs("[OUTPUT]", host_out, count);

    if (cfg.fast_algo)
    {
        // SRamManager cleanup for this case.
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
 * @brief Demo entry point: compare baseline and optimized 2D FFT modes and print speedup.
 * @return 0 on success.
 */
int main()
{
    rppsmgr::SRamManager& smgr = rppsmgr::SRamManager::GetInstance();
    // SRamManager Init: create workspace for fast FFT mode.
    smgr.Init(SRAM_WORK_SPACE);

    Perf2DCaseConfig baseline = {
        "Baseline 2D: normal mode + runtime I/O",
        1024, 128, 20, 200, false, true
    };

    Perf2DCaseConfig optimized = {
        "Optimized 2D: fast mode + fixed I/O",
        1024, 128, 20, 200, true, false
    };

    double baseline_us = run_perf_case_2d(baseline);
    double optimized_us = run_perf_case_2d(optimized);

    printf("\n=================== 2D PERFORMANCE SUMMARY ==================\n");
    printf("Baseline  avg: %10.3f us\n", baseline_us);
    printf("Optimized avg: %10.3f us\n", optimized_us);
    if (optimized_us > 0.0)
    {
        printf("Speedup (baseline/optimized): %.3fx\n", baseline_us / optimized_us);
    }
    printf("============================================================\n");

    // SRamManager Destroy: release workspace before exit.
    smgr.Destroy();
    return 0;
}
