/**
 * @file rpp_tile_based.cu
 * @brief Tile-based ping-pong SRAM demo for C=A+B. See rpp_tile_based/README.md for full workflow.
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
 * @brief Compute one tile element from SRAM inputs: C[y,x] = A[y,x] + B[y,x].
 * @param A Input tile A in SRAM.
 * @param B Input tile B in SRAM.
 * @param pitch Row stride in bytes for full-width rows.
 * @param C Output tile C in SRAM.
 */
__global__ void tile_add_pe(const float* A, const float* B, int pitch, float* C)
{
    // Map each thread to one element inside the current tile.
    const uint16_t y = blockIdx.y * blockDim.y + threadIdx.y;
    const uint16_t x = blockIdx.x * blockDim.x + threadIdx.x;

    // Convert byte pitch to row pointers for pitched 2D layout.
    const float* a_row = (const float*)((const char*)A + y * pitch);
    const float* b_row = (const float*)((const char*)B + y * pitch);
    float* c_row = (float*)((char*)C + y * pitch);

    // Write one output value for this tile coordinate.
    c_row[x] = a_row[x] + b_row[x];
}

/**
 * @brief Run tiled DDR<->SRAM ping-pong pipeline with async streams and events, then print timing and sample outputs.
 * @param none This demo entry function does not consume command-line parameters.
 */
int main()
{
    // Define full matrix shape and tile partitioning.
    const int width = 1024;
    const int height = 128;
    const int tile_height = 16;
    // RISK: tile_count truncates if height is not divisible by tile_height.
    const int tile_count = height / tile_height;
    const int elements = width * height;
    const int tile_elements = width * tile_height;
    // pitch is row bytes; bytes/tile_bytes are full/tile storage sizes.
    const size_t pitch = width * sizeof(float);
    const size_t bytes = elements * sizeof(float);
    const size_t tile_bytes = tile_elements * sizeof(float);

    printf("[RPP hello world tile ping-pong: tiled C = A + B]\n");
    printf("Matrix shape: H=%d, W=%d, elements=%d\n", height, width, elements);
    printf("Tile shape  : tile_h=%d, tile_w=%d, tile_count=%d\n", tile_height, width, tile_count);

    float* h_A = (float*)malloc(bytes);
    float* h_B = (float*)malloc(bytes);
    float* h_C = (float*)malloc(bytes);

    // Stop early if host allocation fails.
    if (h_A == nullptr || h_B == nullptr || h_C == nullptr)
    {
        printf("Host allocation failed\n");
        return 1;
    }

    // Fill deterministic inputs for easy output verification.
    for (int i = 0; i < elements; ++i)
    {
        h_A[i] = (float)((i % 17) + 1);
        h_B[i] = (float)((i % 5) + 1);
        h_C[i] = 0.0f;
    }

    float* d_A = nullptr;
    float* d_B = nullptr;
    float* d_C = nullptr;
    float* sram_A[2] = {nullptr, nullptr};
    float* sram_B[2] = {nullptr, nullptr};
    float* sram_C[2] = {nullptr, nullptr};
    RPPstream transfer_stream = nullptr;
    RPPstream compute_stream = nullptr;
    RPPevent load_done[2] = {nullptr, nullptr};
    RPPevent compute_done[2] = {nullptr, nullptr};

    // rtMalloc: allocate full matrices in device DDR.
    checkRppErrors(rtMalloc((void**)&d_A, bytes));
    checkRppErrors(rtMalloc((void**)&d_B, bytes));
    checkRppErrors(rtMalloc((void**)&d_C, bytes));

    // rtMallocSram: allocate two ping-pong SRAM slots for A/B/C tiles.
    checkRppErrors(rtMallocSram((void**)&sram_A[0], tile_bytes));
    checkRppErrors(rtMallocSram((void**)&sram_A[1], tile_bytes));
    checkRppErrors(rtMallocSram((void**)&sram_B[0], tile_bytes));
    checkRppErrors(rtMallocSram((void**)&sram_B[1], tile_bytes));
    checkRppErrors(rtMallocSram((void**)&sram_C[0], tile_bytes));
    checkRppErrors(rtMallocSram((void**)&sram_C[1], tile_bytes));

    // rppStreamCreate: separate transfer and compute streams for overlap-ready scheduling.
    checkRppErrors(rppStreamCreate(&transfer_stream, 0));
    checkRppErrors(rppStreamCreate(&compute_stream, 0));
    // rppEventCreate: create per-slot events for load-compute and compute-store dependencies.
    checkRppErrors(rppEventCreate(&load_done[0], 0));
    checkRppErrors(rppEventCreate(&load_done[1], 0));
    checkRppErrors(rppEventCreate(&compute_done[0], 0));
    checkRppErrors(rppEventCreate(&compute_done[1], 0));

    dim3 threads(256, 4, 1);
    dim3 blocks(4, 4, 1);

    timeval tv_total_start, tv_h2d_start, tv_h2d_end, tv_tile_start, tv_tile_end;
    timeval tv_d2h_start, tv_d2h_end, tv_total_end;
    struct timezone tz;

    // Start full pipeline timing.
    gettimeofday(&tv_total_start, &tz);

    // Transfer full input matrices from host to device DDR.
    gettimeofday(&tv_h2d_start, &tz);
    // rppMemcpyHtoDAsync: host -> device DDR transfer.
    checkRppErrors(rppMemcpyHtoDAsync((RPPdeviceptr)d_A, h_A, bytes, transfer_stream));
    checkRppErrors(rppMemcpyHtoDAsync((RPPdeviceptr)d_B, h_B, bytes, transfer_stream));
    // rppStreamSynchronize: ensure initial full-matrix copies are complete.
    checkRppErrors(rppStreamSynchronize(transfer_stream));
    gettimeofday(&tv_h2d_end, &tz);

    // Start tile-loop timing region (D2S, compute, S2D across all tiles).
    gettimeofday(&tv_tile_start, &tz);

    // Preload tile 0 into slot0 so compute can start when load_done[0] is signaled.
    // rppMemcpyDtoSAsync: device DDR -> SRAM transfer.
    checkRppErrors(rppMemcpyDtoSAsync((RPPdeviceptr)sram_A[0], (RPPdeviceptr)d_A, tile_bytes, transfer_stream));
    checkRppErrors(rppMemcpyDtoSAsync((RPPdeviceptr)sram_B[0], (RPPdeviceptr)d_B, tile_bytes, transfer_stream));
    // rppEventRecord: mark slot0 load completion for compute stream dependency.
    checkRppErrors(rppEventRecord(load_done[0], transfer_stream));

    // Process tiles in ping-pong order: wait load, compute current, preload next, store current.
    for (int tile = 0; tile < tile_count; ++tile)
    {
        // Select current ping-pong slot and next slot.
        const int current = tile & 1;
        const int next = current ^ 1;
        // tile_offset points to the first element of this tile in full matrices.
        const int tile_offset = tile * tile_elements;

        // rppStreamWaitEvent: start compute when current slot load is ready.
        checkRppErrors(rppStreamWaitEvent(compute_stream, load_done[current], 0));
        tile_add_pe<<<blocks, threads, 0, compute_stream>>>(
            sram_A[current], sram_B[current], (int)pitch, sram_C[current]);
        // rppEventRecord: signal that current slot compute is done.
        checkRppErrors(rppEventRecord(compute_done[current], compute_stream));

        // Preload next tile into the alternate slot while current tile is computing/storing.
        if (tile + 1 < tile_count)
        {
            const int next_offset = (tile + 1) * tile_elements;
            checkRppErrors(rppMemcpyDtoSAsync((RPPdeviceptr)sram_A[next],
                                             (RPPdeviceptr)(d_A + next_offset),
                                             tile_bytes,
                                             transfer_stream));
            checkRppErrors(rppMemcpyDtoSAsync((RPPdeviceptr)sram_B[next],
                                             (RPPdeviceptr)(d_B + next_offset),
                                             tile_bytes,
                                             transfer_stream));
            checkRppErrors(rppEventRecord(load_done[next], transfer_stream));
        }

        // Ensure store waits for compute completion of the same slot.
        checkRppErrors(rppStreamWaitEvent(transfer_stream, compute_done[current], 0));
        // rppMemcpyStoDAsync: SRAM -> device DDR transfer.
        checkRppErrors(rppMemcpyStoDAsync((RPPdeviceptr)(d_C + tile_offset),
                                          (RPPdeviceptr)sram_C[current],
                                          tile_bytes,
                                          transfer_stream));
    }

    // Wait for all queued transfers and kernels to finish before closing tile timing.
    checkRppErrors(rppStreamSynchronize(transfer_stream));
    checkRppErrors(rppStreamSynchronize(compute_stream));
    gettimeofday(&tv_tile_end, &tz);

    // Copy full output matrix back to host memory.
    gettimeofday(&tv_d2h_start, &tz);
    // rppMemcpyDtoHAsync: device DDR -> host transfer.
    checkRppErrors(rppMemcpyDtoHAsync(h_C, (RPPdeviceptr)d_C, bytes, transfer_stream));
    checkRppErrors(rppStreamSynchronize(transfer_stream));
    gettimeofday(&tv_d2h_end, &tz);

    gettimeofday(&tv_total_end, &tz);

    printf("\n=== Pipeline Timeline ===\n");
    printf("H2D full matrix           : %8.3f ms\n", elapsed_ms(tv_h2d_start, tv_h2d_end));
    printf("Tile loop D2S/PE/S2D      : %8.3f ms\n", elapsed_ms(tv_tile_start, tv_tile_end));
    printf("D2H full matrix           : %8.3f ms\n", elapsed_ms(tv_d2h_start, tv_d2h_end));
    printf("Total pipeline            : %8.3f ms\n", elapsed_ms(tv_total_start, tv_total_end));

    printf("\n=== Tile Mechanism ===\n");
    printf("Each tile cycles: DDR tile -> SRAM tile slot -> PE compute -> DDR tile\n");
    printf("Ping-pong slots : slot0 and slot1 alternate by tile index\n");
    printf("Tile count      : %d\n", tile_count);
    printf("Tile bytes      : %zu\n", tile_bytes);

    printf("\n=== Tile Schedule ===\n");
    for (int tile = 0; tile < tile_count; ++tile)
    {
        const int slot = tile & 1;
        printf("tile %d -> slot%d -> PE -> slot%d -> DDR rows [%d, %d)\n",
               tile, slot, slot, tile * tile_height, (tile + 1) * tile_height);
    }

    printf("\n=== Launch Configuration ===\n");
    printf("threads=(%u,%u,%u), blocks=(%u,%u,%u)\n",
           threads.x, threads.y, threads.z, blocks.x, blocks.y, blocks.z);
    printf("PE view: one tile is mapped to one kernel launch, and each thread computes one element inside the tile.\n");

    printf("\n=== First 20 Values ===\n");
    // Print a small output slice for quick correctness check.
    for (int i = 0; i < 20; ++i)
    {
        printf("[%02d] A=%6.1f, B=%6.1f, C=%6.1f\n", i, h_A[i], h_B[i], h_C[i]);
    }

    printf("\n=== Status ===\n");
    printf("Tiled ping-pong pipeline finished successfully.\n");

    // rppEventDestroy/rppStreamDestroy: release sync objects and streams.
    checkRppErrors(rppEventDestroy(load_done[0]));
    checkRppErrors(rppEventDestroy(load_done[1]));
    checkRppErrors(rppEventDestroy(compute_done[0]));
    checkRppErrors(rppEventDestroy(compute_done[1]));
    checkRppErrors(rppStreamDestroy(transfer_stream));
    checkRppErrors(rppStreamDestroy(compute_stream));

    // rtFreeSram: release all SRAM tile slots.
    checkRppErrors(rtFreeSram((void*)sram_A[0]));
    checkRppErrors(rtFreeSram((void*)sram_A[1]));
    checkRppErrors(rtFreeSram((void*)sram_B[0]));
    checkRppErrors(rtFreeSram((void*)sram_B[1]));
    checkRppErrors(rtFreeSram((void*)sram_C[0]));
    checkRppErrors(rtFreeSram((void*)sram_C[1]));

    // rtFree: release full-matrix device DDR buffers.
    checkRppErrors(rtFree((void*)d_A));
    checkRppErrors(rtFree((void*)d_B));
    checkRppErrors(rtFree((void*)d_C));

    // Release host buffers.
    free(h_A);
    free(h_B);
    free(h_C);

    return 0;
}
