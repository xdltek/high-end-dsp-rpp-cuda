/**
 * @file rpp_pingpong.cu
 * @brief Ping-pong SRAM demo with async transfer/compute streams. See rpp_pingpong/README.md for full workflow.
 */

#include <stdio.h>
#include <stdlib.h>
#include <sys/time.h>

#include <rpp_runtime.h>
#include <__clang_cuda_builtin_vars.h>
#include <rpp_com.h>
#include <rpp_drv_api.h>

/**
 * @brief Add two SRAM matrices element-wise and write to an SRAM output matrix.
 * @param A Input matrix A in SRAM.
 * @param B Input matrix B in SRAM.
 * @param pitch Row stride in bytes.
 * @param C Output matrix C in SRAM.
 */
__global__ void pingpong_add(const float* A, const float* B, int pitch, float* C);

/**
 * @brief Multiply two SRAM matrices element-wise and write to an SRAM output matrix.
 * @param A Input matrix A in SRAM.
 * @param B Input matrix B in SRAM.
 * @param pitch Row stride in bytes.
 * @param C Output matrix C in SRAM.
 */
__global__ void pingpong_mul(const float* A, const float* B, int pitch, float* C);

namespace
{
/* Per-stage kernel timing (Add0, Mul, Add1) */
struct StageTiming
{
    float add0_ms;
    float mul_ms;
    float add1_ms;
    float total_ms;
};

/**
 * @brief Compute elapsed time in milliseconds between two wall-clock timestamps.
 * @param start Start timestamp from gettimeofday.
 * @param end End timestamp from gettimeofday.
 */
float elapsed_ms(const timeval& start, const timeval& end)
{
    const double start_us = start.tv_sec * 1000000.0 + start.tv_usec;
    const double end_us = end.tv_sec * 1000000.0 + end.tv_usec;
    return (float)((end_us - start_us) / 1000.0);
}

/**
 * @brief Run one full ping-pong compute sequence on the compute stream: Add -> Mul -> Add.
 * @param sram_ping0 Ping buffer 0 in SRAM.
 * @param sram_ping1 Ping buffer 1 in SRAM.
 * @param sram_B Immutable B buffer in SRAM.
 * @param pitch Row stride in bytes.
 * @param blocks Grid dimensions for kernel launch.
 * @param threads Block dimensions for kernel launch.
 * @param compute_stream Stream used for kernel submissions.
 * @return Per-stage and total timing for this sequence.
 */
StageTiming run_pingpong_sequence_async(float* sram_ping0, float* sram_ping1, float* sram_B,
                                        int pitch, dim3 blocks, dim3 threads, RPPstream compute_stream)
{
    timeval tv_add0_start, tv_add0_end, tv_mul_start, tv_mul_end, tv_add1_start, tv_add1_end;
    timeval tv_total_start, tv_total_end;
    struct timezone tz;

    gettimeofday(&tv_total_start, &tz);

    // Launch the first stage on compute_stream and wait for completion.
    gettimeofday(&tv_add0_start, &tz);
    pingpong_add<<<blocks, threads, 0, compute_stream>>>(sram_ping0, sram_B, pitch, sram_ping1);
    // rppStreamSynchronize: block until queued kernel work on this stream is done.
    checkRppErrors(rppStreamSynchronize(compute_stream));
    gettimeofday(&tv_add0_end, &tz);

    // Launch the second stage and write back to ping0.
    gettimeofday(&tv_mul_start, &tz);
    pingpong_mul<<<blocks, threads, 0, compute_stream>>>(sram_ping1, sram_B, pitch, sram_ping0);
    checkRppErrors(rppStreamSynchronize(compute_stream));
    gettimeofday(&tv_mul_end, &tz);

    // Launch the final stage so the end result lands in ping1.
    gettimeofday(&tv_add1_start, &tz);
    pingpong_add<<<blocks, threads, 0, compute_stream>>>(sram_ping0, sram_B, pitch, sram_ping1);
    checkRppErrors(rppStreamSynchronize(compute_stream));
    gettimeofday(&tv_add1_end, &tz);

    gettimeofday(&tv_total_end, &tz);

    StageTiming timing = {};
    timing.add0_ms = elapsed_ms(tv_add0_start, tv_add0_end);
    timing.mul_ms = elapsed_ms(tv_mul_start, tv_mul_end);
    timing.add1_ms = elapsed_ms(tv_add1_start, tv_add1_end);
    timing.total_ms = elapsed_ms(tv_total_start, tv_total_end);
    return timing;
}
}

/**
 * @brief Kernel implementation for element-wise add: C = A + B.
 * @param A Input matrix A in SRAM.
 * @param B Input matrix B in SRAM.
 * @param pitch Row stride in bytes.
 * @param C Output matrix C in SRAM.
 */
__global__ void pingpong_add(const float* A, const float* B, int pitch, float* C)
{
    // Map this thread to one matrix coordinate.
    const uint16_t y = blockIdx.y * blockDim.y + threadIdx.y;
    const uint16_t x = blockIdx.x * blockDim.x + threadIdx.x;

    // Convert byte pitch to row pointers for 2D access.
    const float* a_row = (const float*)((const char*)A + y * pitch);
    const float* b_row = (const float*)((const char*)B + y * pitch);
    float* c_row = (float*)((char*)C + y * pitch);

    // Write one output element for this coordinate.
    c_row[x] = a_row[x] + b_row[x];
}

/**
 * @brief Kernel implementation for element-wise multiply: C = A * B.
 * @param A Input matrix A in SRAM.
 * @param B Input matrix B in SRAM.
 * @param pitch Row stride in bytes.
 * @param C Output matrix C in SRAM.
 */
__global__ void pingpong_mul(const float* A, const float* B, int pitch, float* C)
{
    // Map this thread to one matrix coordinate.
    const uint16_t y = blockIdx.y * blockDim.y + threadIdx.y;
    const uint16_t x = blockIdx.x * blockDim.x + threadIdx.x;

    // Convert byte pitch to row pointers for 2D access.
    const float* a_row = (const float*)((const char*)A + y * pitch);
    const float* b_row = (const float*)((const char*)B + y * pitch);
    float* c_row = (float*)((char*)C + y * pitch);

    // Write one output element for this coordinate.
    c_row[x] = a_row[x] * b_row[x];
}

/**
 * @brief Run ping-pong async demo with two streams and event dependencies, then print timing and sample outputs.
 * @param none This demo entry function does not consume command-line parameters.
 */
int main()
{
    /* ---------- 1. Problem size ---------- */
    // Choose a fixed shape for clear and repeatable timing comparison.
    const int width = 1024;
    const int height = 32;
    const int elements = width * height;
    // pitch is row bytes; bytes is total matrix storage.
    const size_t pitch = width * sizeof(float);
    const size_t bytes = elements * sizeof(float);

    printf("[rpp_03_pingpong]\n");
    printf("Formula: C = ((A + B) * B) + B\n");
    printf("Matrix shape: H=%d, W=%d, elements=%d\n", height, width, elements);

    /* ---------- 2. Host allocation and init ---------- */
    float* h_A = (float*)malloc(bytes);
    float* h_B = (float*)malloc(bytes);
    float* h_C = (float*)malloc(bytes);

    // Stop early if host allocation fails.
    if (h_A == nullptr || h_B == nullptr || h_C == nullptr)
    {
        printf("Host allocation failed\n");
        return 1;
    }

    // Fill deterministic values so output can be checked by eye.
    for (int i = 0; i < elements; ++i)
    {
        h_A[i] = (float)((i % 11) + 1);
        h_B[i] = (float)((i % 7) + 1);
        h_C[i] = 0.0f;
    }

    /* ---------- 3. Device DRAM and SRAM allocation ---------- */
    float* d_A = nullptr;
    float* d_B = nullptr;
    float* d_C = nullptr;
    float* sram_ping0 = nullptr;
    float* sram_ping1 = nullptr;
    float* sram_B = nullptr;

    /* ---------- 4. Streams and events ---------- */
    /* transfer_stream: H2D, D2S, S2D, D2H. compute_stream: kernel launches */
    RPPstream transfer_stream = nullptr;
    RPPstream compute_stream = nullptr;
    RPPevent d2s_done = nullptr;
    RPPevent reload_done = nullptr;
    RPPevent cold_done = nullptr;
    RPPevent warm_done = nullptr;

    // rtMalloc: allocate device DDR buffers.
    checkRppErrors(rtMalloc((void**)&d_A, bytes));
    checkRppErrors(rtMalloc((void**)&d_B, bytes));
    checkRppErrors(rtMalloc((void**)&d_C, bytes));

    // rtMallocSram: allocate SRAM buffers for ping-pong and constant B input.
    checkRppErrors(rtMallocSram((void**)&sram_ping0, bytes));
    checkRppErrors(rtMallocSram((void**)&sram_ping1, bytes));
    checkRppErrors(rtMallocSram((void**)&sram_B, bytes));
    // rppStreamCreate: create transfer and compute streams for asynchronous submission.
    checkRppErrors(rppStreamCreate(&transfer_stream, 0));
    checkRppErrors(rppStreamCreate(&compute_stream, 0));
    /* d2s_done: D2S finished. reload_done: A reloaded for warm run. cold_done/warm_done: compute done */
    // rppEventCreate: create events used to connect transfer and compute dependencies.
    checkRppErrors(rppEventCreate(&d2s_done, 0));
    checkRppErrors(rppEventCreate(&reload_done, 0));
    checkRppErrors(rppEventCreate(&cold_done, 0));
    checkRppErrors(rppEventCreate(&warm_done, 0));

    /* ---------- 5. Kernel launch config ---------- */
    dim3 threads(1024, 4, 1);
    dim3 blocks(1, 8, 1);

    timeval tv_total_start, tv_h2d_start, tv_h2d_end, tv_d2s_start, tv_d2s_end;
    timeval tv_s2d_start, tv_s2d_end, tv_d2h_start, tv_d2h_end, tv_total_end;
    struct timezone tz;

    // Start full-pipeline wall-clock timing.
    gettimeofday(&tv_total_start, &tz);

    // Enqueue host-to-device DDR copies on the transfer stream.
    gettimeofday(&tv_h2d_start, &tz);
    // rppMemcpyHtoDAsync: host -> device DDR transfer.
    checkRppErrors(rppMemcpyHtoDAsync((RPPdeviceptr)d_A, h_A, bytes, transfer_stream));
    checkRppErrors(rppMemcpyHtoDAsync((RPPdeviceptr)d_B, h_B, bytes, transfer_stream));
    // rppStreamSynchronize: wait until transfer stream completes queued copies.
    checkRppErrors(rppStreamSynchronize(transfer_stream));
    gettimeofday(&tv_h2d_end, &tz);

    // Enqueue device DDR -> SRAM transfers for initial compute inputs.
    gettimeofday(&tv_d2s_start, &tz);
    // rppMemcpyDtoSAsync: device DDR -> SRAM transfer.
    checkRppErrors(rppMemcpyDtoSAsync((RPPdeviceptr)sram_ping0, (RPPdeviceptr)d_A, bytes, transfer_stream));
    checkRppErrors(rppMemcpyDtoSAsync((RPPdeviceptr)sram_B, (RPPdeviceptr)d_B, bytes, transfer_stream));
    // rppEventRecord: mark that initial D2S transfer has been submitted/completed on transfer_stream.
    checkRppErrors(rppEventRecord(d2s_done, transfer_stream));
    checkRppErrors(rppStreamSynchronize(transfer_stream));
    gettimeofday(&tv_d2s_end, &tz);

    // rppStreamWaitEvent: start compute only after initial D2S data is ready.
    checkRppErrors(rppStreamWaitEvent(compute_stream, d2s_done, 0));
    // Execute one full ping-pong sequence as the cold run.
    StageTiming cold_timing = run_pingpong_sequence_async(sram_ping0, sram_ping1, sram_B, (int)pitch, blocks, threads, compute_stream);
    checkRppErrors(rppEventRecord(cold_done, compute_stream));

    // Wait for cold compute completion before reloading ping0.
    checkRppErrors(rppStreamWaitEvent(transfer_stream, cold_done, 0));
    // Reload A from device DDR into ping0 to reset warm-run input state.
    checkRppErrors(rppMemcpyDtoSAsync((RPPdeviceptr)sram_ping0, (RPPdeviceptr)d_A, bytes, transfer_stream));
    checkRppErrors(rppEventRecord(reload_done, transfer_stream));

    // Start warm run only after ping0 reload is complete.
    checkRppErrors(rppStreamWaitEvent(compute_stream, reload_done, 0));
    StageTiming warm_timing = run_pingpong_sequence_async(sram_ping0, sram_ping1, sram_B, (int)pitch, blocks, threads, compute_stream);
    checkRppErrors(rppEventRecord(warm_done, compute_stream));

    // Export final warm-run result from SRAM to device DDR.
    gettimeofday(&tv_s2d_start, &tz);
    checkRppErrors(rppStreamWaitEvent(transfer_stream, warm_done, 0));
    // rppMemcpyStoDAsync: SRAM -> device DDR transfer.
    checkRppErrors(rppMemcpyStoDAsync((RPPdeviceptr)d_C, (RPPdeviceptr)sram_ping1, bytes, transfer_stream));
    checkRppErrors(rppStreamSynchronize(transfer_stream));
    gettimeofday(&tv_s2d_end, &tz);

    // Bring final output from device DDR back to host memory.
    gettimeofday(&tv_d2h_start, &tz);
    // rppMemcpyDtoHAsync: device DDR -> host transfer.
    checkRppErrors(rppMemcpyDtoHAsync(h_C, (RPPdeviceptr)d_C, bytes, transfer_stream));
    checkRppErrors(rppStreamSynchronize(transfer_stream));
    gettimeofday(&tv_d2h_end, &tz);

    gettimeofday(&tv_total_end, &tz);

    printf("\n=== Transfer Timeline ===\n");
    printf("H2D  (Host -> Device DDR) : %8.3f ms\n", elapsed_ms(tv_h2d_start, tv_h2d_end));
    printf("D2S  (Device DDR -> SRAM) : %8.3f ms\n", elapsed_ms(tv_d2s_start, tv_d2s_end));
    printf("S2D  (SRAM -> Device DDR) : %8.3f ms\n", elapsed_ms(tv_s2d_start, tv_s2d_end));
    printf("D2H  (Device DDR -> Host) : %8.3f ms\n", elapsed_ms(tv_d2h_start, tv_d2h_end));
    printf("Total pipeline            : %8.3f ms\n", elapsed_ms(tv_total_start, tv_total_end));

    printf("\n=== Cold Run ===\n");
    printf("Add0 (ping0 -> ping1)     : %8.3f ms\n", cold_timing.add0_ms);
    printf("Mul  (ping1 -> ping0)     : %8.3f ms\n", cold_timing.mul_ms);
    printf("Add1 (ping0 -> ping1)     : %8.3f ms\n", cold_timing.add1_ms);
    printf("Cold run total            : %8.3f ms\n", cold_timing.total_ms);

    printf("\n=== Warm Run ===\n");
    printf("Add0 (ping0 -> ping1)     : %8.3f ms\n", warm_timing.add0_ms);
    printf("Mul  (ping1 -> ping0)     : %8.3f ms\n", warm_timing.mul_ms);
    printf("Add1 (ping0 -> ping1)     : %8.3f ms\n", warm_timing.add1_ms);
    printf("Warm run total            : %8.3f ms\n", warm_timing.total_ms);

    printf("\n=== Launch Configuration ===\n");
    printf("threads=(%u,%u,%u), blocks=(%u,%u,%u)\n",
           threads.x, threads.y, threads.z, blocks.x, blocks.y, blocks.z);

    printf("\n=== Async Mode ===\n");
    printf("transfer_stream: async H2D / D2S / S2D / D2H\n");
    printf("compute_stream : async Add0 / Mul / Add1\n");
    printf("events         : connect transfer and compute dependencies\n");
    printf("advantage      : host does not block at each submission, and this pattern is ready for overlap/pipelining\n");

    printf("\n=== Ping-Pong Buffers ===\n");
    printf("Stage 1: ping0 + B -> ping1\n");
    printf("Stage 2: ping1 * B -> ping0\n");
    printf("Stage 3: ping0 + B -> ping1\n");
    printf("Warm run starts after reloading A back into ping0.\n");

    printf("\n=== First 20 Values ===\n");
    // Show a small output slice for quick correctness inspection.
    for (int i = 0; i < 20; ++i)
    {
        printf("[%02d] A=%6.1f, B=%6.1f, C=%6.1f\n", i, h_A[i], h_B[i], h_C[i]);
    }

    printf("\n=== Status ===\n");
    printf("Pipeline finished successfully.\n");

    /* ---------- 6. Cleanup ---------- */
    // rppEventDestroy/rppStreamDestroy: release synchronization and stream resources.
    checkRppErrors(rppEventDestroy(d2s_done));
    checkRppErrors(rppEventDestroy(reload_done));
    checkRppErrors(rppEventDestroy(cold_done));
    checkRppErrors(rppEventDestroy(warm_done));
    checkRppErrors(rppStreamDestroy(transfer_stream));
    checkRppErrors(rppStreamDestroy(compute_stream));

    // rtFreeSram: release SRAM buffers.
    checkRppErrors(rtFreeSram((void*)sram_ping0));
    checkRppErrors(rtFreeSram((void*)sram_ping1));
    checkRppErrors(rtFreeSram((void*)sram_B));

    // rtFree: release device DDR buffers.
    checkRppErrors(rtFree((void*)d_A));
    checkRppErrors(rtFree((void*)d_B));
    checkRppErrors(rtFree((void*)d_C));

    // Release host buffers.
    free(h_A);
    free(h_B);
    free(h_C);

    return 0;
}
