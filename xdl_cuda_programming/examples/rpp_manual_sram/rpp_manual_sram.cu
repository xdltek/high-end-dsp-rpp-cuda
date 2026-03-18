/**
 * @file rpp_manual_sram.cu
 * @brief Manual SRAM demo for C=A+B with explicit DDR<->SRAM copies. See rpp_manual_sram/README.md for full workflow.
 */

#include <stdio.h>
#include <stdlib.h>
#include <sys/time.h>

#include <rpp_runtime.h>
#include <__clang_cuda_builtin_vars.h>
#include <rpp_com.h>
#include <rpp_drv_api.h>

namespace
{
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
}

/**
 * @brief Compute one matrix element from SRAM inputs: C[y,x] = A[y,x] + B[y,x].
 * @param A Input matrix A in SRAM.
 * @param B Input matrix B in SRAM.
 * @param pitch Row stride in bytes.
 * @param C Output matrix C in SRAM.
 */
__global__ void hello_world_add_manual(const float* A, const float* B,
                                       int pitch, float* C)
{
    // Map this thread to one matrix coordinate.
    const uint16_t y = blockIdx.y * blockDim.y + threadIdx.y;
    const uint16_t x = blockIdx.x * blockDim.x + threadIdx.x;

    // Convert byte pitch to row pointers for 2D access.
    const float* a_row = (const float*)((const char*)A + y * pitch);
    const float* b_row = (const float*)((const char*)B + y * pitch);
    float* c_row = (float*)((char*)C + y * pitch);

    // Write the output element for this coordinate.
    c_row[x] = a_row[x] + b_row[x];
}

/**
 * @brief Run the manual-SRAM pipeline: allocate buffers, perform transfers, launch kernel, and print timing/output.
 * @param none This demo entry function does not consume command-line parameters.
 */
int main()
{
    /* ---------- 1. Problem size ---------- */
    // Keep dimensions simple so users can focus on memory movement first.
    const int width = 1024;
    const int height = 32;
    const int elements = width * height;
    // pitch is row bytes; bytes is full matrix storage.
    const size_t pitch = width * sizeof(float);
    const size_t bytes = elements * sizeof(float);

    printf("[rpp_02_manual_sram: C = A + B]\n");
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

    // Initialize deterministic input data for quick visual validation.
    for (int i = 0; i < elements; ++i)
    {
        h_A[i] = (float)(i % 13);
        h_B[i] = (float)(i % 7);
        h_C[i] = 0.0f;
    }

    /* ---------- 3. Device DRAM allocation ---------- */
    float* d_A = nullptr;
    float* d_B = nullptr;
    float* d_C = nullptr;
    float* sram_A = nullptr;
    float* sram_B = nullptr;
    float* sram_C = nullptr;

    // rtMalloc: allocate device DDR buffers on the RPP card.
    checkRppErrors(rtMalloc((void**)&d_A, bytes));
    checkRppErrors(rtMalloc((void**)&d_B, bytes));
    checkRppErrors(rtMalloc((void**)&d_C, bytes));

    /* ---------- 4. Manual SRAM allocation (one buffer per matrix) ---------- */
    // rtMallocSram: explicitly allocate SRAM buffers for manual dataflow control.
    checkRppErrors(rtMallocSram((void**)&sram_A, bytes));
    checkRppErrors(rtMallocSram((void**)&sram_B, bytes));
    checkRppErrors(rtMallocSram((void**)&sram_C, bytes));

    /* ---------- 5. Kernel launch config ---------- */
    dim3 threads(1024, 4, 1);
    dim3 blocks(1, 8, 1);

    timeval tv_total_start, tv_h2d_start, tv_h2d_end, tv_d2s_start, tv_d2s_end;
    timeval tv_kernel_start, tv_kernel_end, tv_s2d_start, tv_s2d_end, tv_d2h_start, tv_d2h_end, tv_total_end;
    struct timezone tz;

    // Start full-pipeline wall-clock timing.
    gettimeofday(&tv_total_start, &tz);

    /* Step 1: Host -> Device DRAM */
    // Measure host -> device DDR transfer for both inputs.
    gettimeofday(&tv_h2d_start, &tz);
    // rtMemcpy: host -> device DDR copy.
    checkRppErrors(rtMemcpy(d_A, h_A, bytes, rtMemcpyHostToDevice));
    checkRppErrors(rtMemcpy(d_B, h_B, bytes, rtMemcpyHostToDevice));
    gettimeofday(&tv_h2d_end, &tz);

    /* Step 2: Device DRAM -> SRAM (DtoS) */
    // Measure loading inputs from device DDR into SRAM.
    gettimeofday(&tv_d2s_start, &tz);
    // rtMemcpy with rtMemcpyDeviceToSram: device DDR -> SRAM.
    checkRppErrors(rtMemcpy(sram_A, d_A, bytes, rtMemcpyDeviceToSram));
    checkRppErrors(rtMemcpy(sram_B, d_B, bytes, rtMemcpyDeviceToSram));
    gettimeofday(&tv_d2s_end, &tz);

    /* Step 3: Kernel runs on SRAM buffers */
    // Measure compute stage that reads/writes only SRAM buffers.
    gettimeofday(&tv_kernel_start, &tz);
    hello_world_add_manual<<<blocks, threads>>>(sram_A, sram_B, (int)pitch, sram_C);
    // rtDeviceSynchronize: wait until kernel execution completes.
    checkRppErrors(rtDeviceSynchronize());
    gettimeofday(&tv_kernel_end, &tz);

    /* Step 4: SRAM -> Device DRAM (StoD) */
    // Measure storing result from SRAM back to device DDR.
    gettimeofday(&tv_s2d_start, &tz);
    // rtMemcpy with rtMemcpySramToDevice: SRAM -> device DDR.
    checkRppErrors(rtMemcpy(d_C, sram_C, bytes, rtMemcpySramToDevice));
    gettimeofday(&tv_s2d_end, &tz);

    /* Step 5: Device DRAM -> Host */
    // Measure final copy of result back to host memory.
    gettimeofday(&tv_d2h_start, &tz);
    // rtMemcpy: device DDR -> host copy.
    checkRppErrors(rtMemcpy(h_C, d_C, bytes, rtMemcpyDeviceToHost));
    gettimeofday(&tv_d2h_end, &tz);

    gettimeofday(&tv_total_end, &tz);

    printf("\n=== Transfer / Kernel Timeline ===\n");
    printf("H2D  (Host -> Device DDR) : %8.3f ms\n", elapsed_ms(tv_h2d_start, tv_h2d_end));
    printf("D2S  (Device DDR -> SRAM) : %8.3f ms\n", elapsed_ms(tv_d2s_start, tv_d2s_end));
    printf("Kernel (SRAM compute)     : %8.3f ms\n", elapsed_ms(tv_kernel_start, tv_kernel_end));
    printf("S2D  (SRAM -> Device DDR) : %8.3f ms\n", elapsed_ms(tv_s2d_start, tv_s2d_end));
    printf("D2H  (Device DDR -> Host) : %8.3f ms\n", elapsed_ms(tv_d2h_start, tv_d2h_end));
    printf("Total pipeline            : %8.3f ms\n", elapsed_ms(tv_total_start, tv_total_end));

    printf("\n=== Launch Configuration ===\n");
    printf("threads=(%u,%u,%u), blocks=(%u,%u,%u)\n",
           threads.x, threads.y, threads.z, blocks.x, blocks.y, blocks.z);

    printf("\n=== First 10 Values ===\n");
    // Print a small slice to confirm output correctness.
    for (int i = 0; i < 10; ++i)
    {
        printf("[%02d] A=%6.1f, B=%6.1f, C=%6.1f\n", i, h_A[i], h_B[i], h_C[i]);
    }

    printf("\n=== Status ===\n");
    printf("Pipeline finished successfully.\n");

    /* ---------- 6. Cleanup ---------- */
    // rtFreeSram: release manual SRAM allocations.
    checkRppErrors(rtFreeSram((void*)sram_A));
    checkRppErrors(rtFreeSram((void*)sram_B));
    checkRppErrors(rtFreeSram((void*)sram_C));

    // rtFree: release device DDR allocations.
    checkRppErrors(rtFree((void*)d_A));
    checkRppErrors(rtFree((void*)d_B));
    checkRppErrors(rtFree((void*)d_C));

    // Release host allocations.
    free(h_A);
    free(h_B);
    free(h_C);

    return 0;
}
