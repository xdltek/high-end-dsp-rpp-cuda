/**
 * @file rpp_first_demo.cu
 * @brief First RPP demo for C=A+B using SRamManager. See rpp_first_demo/README.md for full workflow.
 */

#include <stdio.h>
#include <stdlib.h>

#include <rpp_runtime.h>
#include <__clang_cuda_builtin_vars.h>
#include <rpp_com.h>
#include <rpp_drv_api.h>
#include <rpp_smgr.h>
#include <rpp_block_segment.h>

/**
 * @brief Compute one matrix element with pitched 2D addressing: C[y,x] = A[y,x] + B[y,x].
 * @param A Input matrix A in SRAM.
 * @param B Input matrix B in SRAM.
 * @param in_pitch Row stride in bytes for A and B.
 * @param C Output matrix C in SRAM.
 * @param out_pitch Row stride in bytes for C.
 */
__global__ void hello_world_add(const float* A, const float* B,
                                int in_pitch, float* C, int out_pitch)
{
    // Map this thread to one 2D matrix coordinate.
    const uint16_t y = blockIdx.y * blockDim.y + threadIdx.y;
    const uint16_t x = blockIdx.x * blockDim.x + threadIdx.x;

    // Convert byte pitch to row pointers for pitched memory access.
    const float* a_row = (const float*)((const char*)A + y * in_pitch);
    const float* b_row = (const float*)((const char*)B + y * in_pitch);
    float* c_row = (float*)((char*)C + y * out_pitch);

    // Write one output element for this thread coordinate.
    c_row[x] = a_row[x] + b_row[x];
}

/**
 * @brief Run the full first-demo flow: allocate buffers, move data, launch kernel, and print sample outputs.
 * @param none This demo entry function does not consume command-line parameters.
 */
int main()
{
    /* ---------- 1. Matrix dimensions ---------- */
    // Use a small 2D problem size so beginners can focus on data flow first.
    const int width = 1024;
    const int height = 32;
    const int elements = width * height;
    // pitch is one row in bytes; bytes is total matrix storage.
    const size_t pitch = width * sizeof(float);
    const size_t bytes = elements * sizeof(float);

    printf("[rpp_first_demo: C = A + B]\n");
    printf("Matrix shape: H=%d, W=%d, elements=%d\n", height, width, elements);

    /* ---------- 2. Host allocation and init ---------- */
    float* h_A = (float*)malloc(bytes);
    float* h_B = (float*)malloc(bytes);
    float* h_C = (float*)malloc(bytes);

    // Stop early if host memory allocation fails.
    if (h_A == nullptr || h_B == nullptr || h_C == nullptr)
    {
        printf("Host allocation failed\n");
        return 1;
    }

    // Fill deterministic input values for easy visual verification.
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

    // rtMalloc: allocate matrices in device DDR memory on the RPP card.
    checkRppErrors(rtMalloc((void**)&d_A, bytes));
    checkRppErrors(rtMalloc((void**)&d_B, bytes));
    checkRppErrors(rtMalloc((void**)&d_C, bytes));

    /* ---------- 4. SRamManager: register buffers for automatic SRAM mapping ---------- */
    /* PitchAllocate tells SRamManager the matrix layout so it can set up SRAM correctly */
    rppsmgr::SRamManager& smgr = rppsmgr::SRamManager::GetInstance();
    // smgr.Init: initialize SRAM workspace management.
    if (smgr.Init(SRAM_WORKSPACE) != rppsmgr::SUCCESS)
    {
        printf("SRamManager error: smgr.Init failed\n");
        return 1;
    }

    // smgr.PitchAllocate: bind each device DDR buffer to an SRAM fragment with pitched layout.
    if (smgr.PitchAllocate(d_A, height, pitch, sizeof(float), HFMT) != rppsmgr::SUCCESS)
    {
        printf("SRamManager error: smgr.PitchAllocate(d_A) failed\n");
        return 1;
    }
    if (smgr.PitchAllocate(d_B, height, pitch, sizeof(float), HFMT) != rppsmgr::SUCCESS)
    {
        printf("SRamManager error: smgr.PitchAllocate(d_B) failed\n");
        return 1;
    }
    if (smgr.PitchAllocate(d_C, height, pitch, sizeof(float), HFMT) != rppsmgr::SUCCESS)
    {
        printf("SRamManager error: smgr.PitchAllocate(d_C) failed\n");
        return 1;
    }

    /* ---------- 5. Kernel launch config ---------- */
    dim3 threads;
    dim3 blocks;
    // BlockDim2d: derive launch geometry that matches this matrix shape.
    BlockDim2d(threads, blocks, height, width);

    /* ---------- 6. Data flow ---------- */

    // Move host input matrices into device DDR before SRAM download.
    // rtMemcpy: host -> device DDR transfer.
    checkRppErrors(rtMemcpy(d_A, h_A, bytes, rtMemcpyHostToDevice));
    checkRppErrors(rtMemcpy(d_B, h_B, bytes, rtMemcpyHostToDevice));

    // Load input matrices from device DDR to SRAM-managed addresses.
    // smgr.Download: device DDR -> SRAM transfer for the registered buffer.
    if (smgr.Download(d_A) != rppsmgr::SUCCESS)
    {
        printf("SRamManager error: smgr.Download(d_A) failed\n");
        return 1;
    }
    if (smgr.Download(d_B) != rppsmgr::SUCCESS)
    {
        printf("SRamManager error: smgr.Download(d_B) failed\n");
        return 1;
    }

    // Launch compute on SRAM pointers returned by SRamManager.
    // smgr.GetSRamAddr: get SRAM address mapped to a device DDR buffer.
    hello_world_add<<<blocks, threads>>>(
        (const float*)smgr.GetSRamAddr(d_A),
        (const float*)smgr.GetSRamAddr(d_B),
        (int)pitch,
        (float*)smgr.GetSRamAddr(d_C),
        (int)pitch);
    // rtDeviceSynchronize: wait until kernel execution finishes.
    checkRppErrors(rtDeviceSynchronize());

    // Write result matrix back from SRAM to device DDR.
    // smgr.Upload: SRAM -> device DDR transfer for the registered buffer.
    if (smgr.Upload(d_C) != rppsmgr::SUCCESS)
    {
        printf("SRamManager error: smgr.Upload(d_C) failed\n");
        return 1;
    }

    // Copy result from device DDR to host memory for display.
    // rtMemcpy: device DDR -> host transfer.
    checkRppErrors(rtMemcpy(h_C, d_C, bytes, rtMemcpyDeviceToHost));

    printf("\n=== Launch Configuration ===\n");
    printf("threads=(%u,%u,%u), blocks=(%u,%u,%u)\n",
           threads.x, threads.y, threads.z, blocks.x, blocks.y, blocks.z);

    printf("\n=== First 10 Values ===\n");
    // Show a small output slice so beginners can confirm C=A+B quickly.
    for (int i = 0; i < 10; ++i)
    {
        printf("[%02d] A=%6.1f, B=%6.1f, C=%6.1f\n", i, h_A[i], h_B[i], h_C[i]);
    }

    printf("\n=== Status ===\n");
    printf("All steps completed successfully.\n");

    /* ---------- 7. Cleanup ---------- */
    // smgr.Destroy: release SRAM manager workspace and internal mappings.
    smgr.Destroy();

    // Free device DDR allocations.
    if (d_A != nullptr) checkRppErrors(rtFree(d_A));
    if (d_B != nullptr) checkRppErrors(rtFree(d_B));
    if (d_C != nullptr) checkRppErrors(rtFree(d_C));

    // Free host allocations.
    free(h_A);
    free(h_B);
    free(h_C);

    return 0;
}
