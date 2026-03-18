/**
 * @file rpp_fft_v4.cpp
 * @brief RPP FFT demo with 1D/2D execution and CPU-reference verification. See rpp_fft/README.md for full workflow.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "rpp_drv_api.h"
#include <rppfft.h>
#include <rpp_runtime.h>
#include <rpp_smgr.h>


/**
 * @brief Reverse lower n bits for radix-2 FFT bit-reversal indexing.
 * @param a Input index.
 * @param n Number of bits.
 * @return Bit-reversed integer.
 */
static int ReverseBin(int a, int n)
{
    int ret = 0;
    for (int i = 0; i < n; i++)
    {
        if (a&(1 << i)) ret |= (1 << (n - 1 - i));
    }
    return ret;
}
/**
 * @brief Apply 1D fftshift on batched complex data in place.
 * @param data Complex buffer.
 * @param batch Batch count.
 * @param count FFT length.
 */
void fftshift_cpu_batch(rppfftComplex *data, int batch, int count)
{
    int k = 0;
    int c = count / 2;
    if (count % 2 == 0)
    {
        for(int b = 0; b < batch; b++)
        {
            for (k = 0; k < c; k++)
            {
                int index0 = k * batch + b;
                int index1 = (k + c) * batch + b;
                rppfftComplex tmp = data[index0];
                data[index0] = data[index1];
                data[index1] = tmp;
            }
        }
    }
    else
    {
        assert(0);
        for(int b = 0; b < batch; b++)
        {
            rppfftComplex tmp = data[0];
            for (k = 0; k < c; k++)
            {
                data[k] = data[c + k + 1];
                data[c + k + 1] = data[k + 1];
            }
            data[c] = tmp;
        }

    }
}
/**
 * @brief CPU reference FFT along column direction for 1D/2D stages.
 * @param batch Number of FFT instances.
 * @param input Input complex buffer.
 * @param output Output complex buffer.
 * @param lim FFT length.
 * @param direction Transform direction.
 * @param isShift Whether fftshift is enabled.
 * @param isFft2D Whether called from 2D path.
 */
void fft_col_cpu(int batch, rppfftComplex *input, rppfftComplex *output, int lim, int direction, int isShift, int isFft2D)
{
    int index;
    rppfftComplex *inputTmp, *outTmp;
    rppfftComplex *tempA = (rppfftComplex *)malloc(lim * sizeof(rppfftComplex));
    rppfftComplex *WN = (rppfftComplex *)malloc((lim / 2) * sizeof(rppfftComplex));
    const float PI = acos(-1);
    for (int i = 0; i < lim / 2; i++)
    {
        WN[i].x = cos(2 * PI * i / lim);
        if (direction == RPPFFT_FORWARD)
            WN[i].y = -sin(2 * PI * i / lim);
        else
            WN[i].y = sin(2 * PI * i / lim);
    }
    
    if (isShift)
        fftshift_cpu_batch(input, batch, lim);
    
    for(int n = 0; n < batch; n++)
    {
        inputTmp = &input[n];
        outTmp = &output[n];
        for (int i = 0; i < lim; i++)
        {
            index = ReverseBin(i, log2(lim));
            tempA[i] = inputTmp[index*batch];
        }
        int Index0, Index1;
        rppfftComplex temp, a, b, c, d, w;
        for (int steplen = 2; steplen <= lim; steplen *= 2)
        {
            for (int step = 0; step < lim / steplen; step++)
            {
                for (int i = 0; i < steplen / 2; i++)
                {
                    Index0 = steplen * step + i;
                    Index1 = steplen * step + i + steplen / 2;
                    a.x = tempA[Index0].x;
                    a.y = tempA[Index0].y;
                    b.x = tempA[Index1].x;
                    b.y = tempA[Index1].y;
                    w = WN[lim / steplen * i];
                    temp.x = b.x * w.x - b.y * w.y; 
                    temp.y = b.x * w.y + b.y * w.x;
                    c.x = a.x + temp.x; 
                    c.y = a.y + temp.y;
                    d.x = a.x - temp.x;
                    d.y = a.y - temp.y;
                    tempA[Index0] = c;
                    tempA[Index1] = d;
                }
            }
        }


        if (direction == RPPFFT_FORWARD || isFft2D == 1)
        {
            for (int i = 0; i < lim; i++)
            {
                outTmp[i*batch].x = tempA[i].x ;
                outTmp[i*batch].y = tempA[i].y ;
            }
        }
        else
        {
            for (int i = 0; i < lim; i++)
            {
                outTmp[i*batch].x = tempA[i].x / lim;
                outTmp[i*batch].y = tempA[i].y / lim;
            }
        }

    }
    free(WN);
    free(tempA);
}
/**
 * @brief CPU reference FFT along row direction for 1D/2D stages.
 * @param batch Number of FFT instances.
 * @param input Input complex buffer.
 * @param output Output complex buffer.
 * @param lim FFT length.
 * @param direction Transform direction.
 * @param isShift Whether fftshift is enabled.
 * @param isFft2D Whether called from 2D path.
 */
static void fft_row_cpu(int batch, rppfftComplex *input, rppfftComplex *output, int lim, int direction, int isShift, int isFft2D)
{
    int index;
    rppfftComplex *inputTmp, *outTmp;
    rppfftComplex *tempA = (rppfftComplex *)malloc(lim * sizeof(rppfftComplex));
    rppfftComplex *WN = (rppfftComplex *)malloc((lim / 2) * sizeof(rppfftComplex));
    const float PI = acos(-1);
    for (int i = 0; i < lim / 2; i++)
    {
        WN[i].x = cos(2 * PI * i / lim);
        if (direction == RPPFFT_FORWARD)
            WN[i].y = -sin(2 * PI * i / lim);
        else
            WN[i].y = sin(2 * PI * i / lim);
    }
    for(int n = 0; n < batch; n++)
    {
        inputTmp = &input[n * lim];
        outTmp = &output[n * lim];
        for (int i = 0; i < lim; i++)
        {
            index = ReverseBin(i, log2(lim));
            tempA[i] = inputTmp[index];
        }
        int Index0, Index1;
        rppfftComplex temp, a, b, c, d, w;
        for (int steplen = 2; steplen <= lim; steplen *= 2)
        {
            for (int step = 0; step < lim / steplen; step++)
            {
                for (int i = 0; i < steplen / 2; i++)
                {
                    Index0 = steplen * step + i;
                    Index1 = steplen * step + i + steplen / 2;
                    a.x = tempA[Index0].x;
                    a.y = tempA[Index0].y;
                    b.x = tempA[Index1].x;
                    b.y = tempA[Index1].y;
                    w = WN[lim / steplen * i];
                    temp.x = b.x * w.x - b.y * w.y; 
                    temp.y = b.x * w.y + b.y * w.x;
                    c.x = a.x + temp.x; 
                    c.y = a.y + temp.y;
                    d.x = a.x - temp.x;
                    d.y = a.y - temp.y;
                    tempA[Index0] = c;
                    tempA[Index1] = d;
                }
            }
        }
        if (direction == RPPFFT_FORWARD || isFft2D == 1)
        {
            for (int i = 0; i < lim; i++)
            {
                outTmp[i].x = tempA[i].x ;
                outTmp[i].y = tempA[i].y ;
            }
        }
        else
        {
            for (int i = 0; i < lim; i++)
            {
                outTmp[i].x = tempA[i].x / lim;
                outTmp[i].y = tempA[i].y / lim;
            }
        }

    }

    free(WN);
    free(tempA);
}
/**
 * @brief Transpose a complex matrix through a temporary host buffer.
 * @param output Matrix buffer.
 * @param H Height.
 * @param W Width.
 */
void complexTranspose(rppfftComplex *output, int H, int W)
{
    rppfftComplex *pTemp = (rppfftComplex * )malloc(H * W * sizeof(rppfftComplex));
    int inOffset, outOffset;
    for(int h = 0; h < H; h++)
        for(int w = 0; w < W; w++)
        {
            inOffset = h * W + w;
            outOffset = w * H + h;
            pTemp[outOffset] = output[inOffset];
        }
    memcpy(output, pTemp, H * W * sizeof(rppfftComplex));

    free(pTemp);

}
/**
 * @brief Apply 2D fftshift by swapping matrix quadrants.
 * @param output Matrix buffer.
 * @param H Height.
 * @param W Width.
 */
void complexFftShift2D(rppfftComplex *output, int H, int W)
{
    rppfftComplex *pTemp = (rppfftComplex * )malloc(H * W * sizeof(rppfftComplex));
    rppfftComplex *src, *dst;
    int inOffset, outOffset;
    int Hm = H >> 1;
    int Wm = W >> 1;
    for(int h = 0; h < Hm; h++)
        for(int w = 0; w < Wm; w++)
        {
            inOffset = h * W + w;
            outOffset = (Hm + h) * W + (Wm + w);
            //copy 1st quad to 4th quad 
            pTemp[outOffset] = output[inOffset];
            //copy 4th quad to 1st quad 
            pTemp[inOffset] = output[outOffset];

            inOffset = h * W + (Wm + w);
            outOffset = (Hm + h) * W + w;
             //copy 2nd quad to 3rd quad 
            pTemp[outOffset] = output[inOffset];
            //copy 3rd quad to 2nd quad 
            pTemp[inOffset] = output[outOffset];           
        }
    memcpy(output, pTemp, H * W * sizeof(rppfftComplex));
    free(pTemp);
}
/**
 * @brief CPU reference 2D FFT: row FFT then column FFT.
 * @param src Input matrix.
 * @param dst Output matrix.
 * @param height Matrix height.
 * @param width Matrix width.
 * @param direction Transform direction.
 */
void fft2d_cpu(rppfftComplex *src, rppfftComplex *dst, int height, int width, int direction)
{
    rppfftComplex *temp = (rppfftComplex *)malloc(width * height * sizeof(rppfftComplex));
    fft_row_cpu(height, src, temp, width, direction, 0, 1);
    fft_col_cpu(width, temp, dst, height, direction, 0, 1);
    free(temp);
}
 
/**
 * @brief CPU reference 1D FFT for batched input.
 * @param src Input buffer.
 * @param dst Output buffer.
 * @param batch Batch count.
 * @param size FFT length.
 * @param direction Transform direction.
 * @param isShift Whether fftshift is enabled.
 * @param columnFft Whether column-major interpretation is used.
 */
void fft1d_cpu(rppfftComplex *src, rppfftComplex *dst, int batch, int size, int direction, bool isShift, bool columnFft)
{
    if(columnFft)
        fft_col_cpu(batch, src, dst, size, direction, isShift, 0);
    else
    {
        fft_row_cpu(batch, src, dst, size, direction, isShift, 0);
        complexTranspose(dst, batch, size);
    }
}
/**
 * @brief Extract option token after '-' from command-line input.
 * @param str Raw command token.
 * @return Parsed option name.
 */
static inline std::string extractCmd(std::string str)
{
    int pos;
    std::string cmd;
    
    pos = (int)str.find_first_of("-", 0);
    if(pos >= 0)
        cmd = str.substr(pos+1, str.size() - (pos+1));
    else
        assert(0);
    
    return cmd;
}
/**
 * @brief Compare RPP output with CPU reference and compute normalized MSE.
 * @param rppOut RPP output.
 * @param cpuOut CPU reference output.
 * @param length Number of elements.
 * @param mse_agv Output MSE value.
 * @return True if error is below threshold.
 */
static bool VerifyOutput(rppfftComplex *rppOut, rppfftComplex *cpuOut, int length, float &mse_agv)
{
    float err_x, err_y, pow_x, pow_y, mse, mse_acc;
    float err_acc, pow_acc;
    mse_acc = 0;
    err_acc = 0;
    pow_acc = 0;
    for(int i = 0; i < length; i++)
    {
        err_x = rppOut[i].x - cpuOut[i].x;
        err_x = err_x * err_x;

        err_y = rppOut[i].y - cpuOut[i].y;
        err_y = err_y * err_y;

        pow_x = rppOut[i].x * rppOut[i].x + cpuOut[i].x * cpuOut[i].x;
        pow_y = rppOut[i].y * rppOut[i].y + cpuOut[i].y * cpuOut[i].y;
        err_acc += (err_x + err_y);
        pow_acc += (pow_x + pow_y);
    }
    mse_agv = err_acc / pow_acc;
    if(mse_agv < 0.0005)
        return true;
    else
        return false;
}
/**
 * @brief Fill deterministic complex input for FFT testing.
 * @param input Buffer to fill.
 * @param height Height or batch dimension.
 * @param width Width or FFT length.
 * @param columnFft Whether to fill with column-major addressing.
 */
void generateInput(rppfftComplex *input, int height, int width, bool columnFft)
{
    int cnt = 0;
    // RISK: columnFft parameter is currently not used; input is always filled in column-major order.
    for(int h = 0; h < height; h++)
    {
        for (int w = 0; w < width; w++)
        {
            input[w * height + h].x = cnt++;
            input[w * height + h].y = 0;
        }
    }
}
 
/**
 * @brief Print first 64 (or fewer) 1D input/output pairs.
 * @param tag Section title.
 * @param input Input buffer.
 * @param output Output buffer.
 * @param batch Batch count.
 * @param fftSize FFT size.
 * @param columnFft Whether output indexing uses column-major mapping.
 */
static void printFirstInputOutputValues1D(const char *tag,
                                          const rppfftComplex *input,
                                          const rppfftComplex *output,
                                          int batch,
                                          int fftSize,
                                          bool columnFft)
{
    int totalCount = batch * fftSize;
    int count = totalCount < 64 ? totalCount : 64;
    printf("%s First %d values (Input -> Output), 2 Groups Per Line:\n", tag, count);
    for (int i = 0; i < count; i++)
    {
        int b = i / fftSize;
        int k = i % fftSize;
        int idx = columnFft ? (k * batch + b) : (b * fftSize + k);
        printf("[%02d] in=(%8.3f,%8.3f) out=(%8.3f,%8.3f)  ",
               i, input[idx].x, input[idx].y, output[idx].x, output[idx].y);
        if (((i + 1) % 2 == 0) || (i + 1 == count))
        {
            printf("\n");
        }
    }
}

/**
 * @brief Print first 64 (or fewer) 2D input/output pairs.
 * @param tag Section title.
 * @param input Input matrix buffer.
 * @param output Output matrix buffer.
 * @param height Matrix height.
 * @param width Matrix width.
 */
static void printFirstInputOutputValues2D(const char *tag,
                                          const rppfftComplex *input,
                                          const rppfftComplex *output,
                                          int height,
                                          int width)
{
    int totalCount = height * width;
    int count = totalCount < 64 ? totalCount : 64;
    printf("%s First %d values (Input -> Output), 2 Groups Per Line:\n", tag, count);
    for (int i = 0; i < count; i++)
    {
        int h = i / width;
        int w = i % width;
        int idx = h * width + w;
        printf("[%02d] in=(%8.3f,%8.3f) out=(%8.3f,%8.3f)  ",
               i, input[idx].x, input[idx].y, output[idx].x, output[idx].y);
        if (((i + 1) % 2 == 0) || (i + 1 == count))
        {
            printf("\n");
        }
    }
}



/**
 * @brief Run one 1D FFT case on RPP and verify against CPU reference.
 * @param batch Batch count.
 * @param fftSize FFT length.
 * @param direction Transform direction.
 * @param isShift Whether fftshift is enabled.
 * @param columnFft Whether column-major interpretation is used.
 * @param fastAlgo Whether fast SRAM path is enabled.
 * @param runtimeIo Whether plan uses runtime I/O mode.
 */
static void runTest1d(int batch, int fftSize, int direction, bool isShift, bool columnFft, bool fastAlgo, bool runtimeIo)
{
    printf("\n============================================================\n");
    printf("[DEMO START] FFT 1D | columnFft=%d | batch=%d | fftSize=%d\n",
           (int)columnFft, batch, fftSize);
    printf("============================================================\n");

    rtError_t err = rtSuccess;
    rppfftResult ret;
    rppfftHandle rppfftForwrdHandle; rtStream_t stream;
    struct timezone tz; struct timeval tv0; struct timeval tv1; struct timeval tv2; struct timeval tv3;
    uint64_t tm0, tm1, tm2, tm3;
    int length = fftSize;
    int size = length * batch * sizeof(rppfftComplex);
    rppfftComplex* host_in, *host_out, *device_in, *device_out;
    rppsmgr::SRamManager& smgr = rppsmgr::SRamManager::GetInstance();

    assert(rtSuccess == rtMallocHost((void**)&host_in, size));
    assert(rtSuccess == rtMallocHost((void**)&host_out, size));

    generateInput(host_in, batch, length, columnFft);

    assert(rtSuccess == rtMalloc((void**)&device_in,  size));
    assert(rtSuccess == rtMalloc((void**)&device_out,  size));

    // rtMemcpy: host -> device DDR input copy.
    assert(rtSuccess == rtMemcpy(device_in, host_in,  size, rtMemcpyHostToDevice));

    if(fastAlgo)
    {
        //fast algo only support fft size < 512K
        assert(batch * fftSize <= FAST_FFT_SIZE);
        // SRamManager: register fast-path SRAM mappings and prepare input format.
        smgr.Allocate(device_in, batch, length, sizeof(rppfftComplex), HCFMT);
        smgr.Allocate(device_out, batch, length, sizeof(rppfftComplex), RCFMT);
        smgr.Download(device_in);
        smgr.ReformatInPlace(device_in);
        if(runtimeIo)
            // rppfftPlan1d: build plan in runtime I/O mode.
            ret = rppfftPlan1d(&rppfftForwrdHandle, length, RPPFFT_C2C, batch, isShift, columnFft, fastAlgo);
        else
            // rppfftPlan1d: build plan in fixed I/O mode.
            ret = rppfftPlan1d(&rppfftForwrdHandle, length, RPPFFT_C2C, batch, isShift, columnFft, fastAlgo, device_in, device_out, direction);
    }
    else
    {
        if(runtimeIo)
            ret = rppfftPlan1d(&rppfftForwrdHandle, length, RPPFFT_C2C, batch, isShift, columnFft, fastAlgo);
        else
            ret = rppfftPlan1d(&rppfftForwrdHandle, length, RPPFFT_C2C, batch, isShift, columnFft, fastAlgo, device_in, device_out, direction);
    }


    assert(ret == RPPFFT_SUCCESS);
    // rppfftSetStream: bind FFT execution to this stream.
    rtStreamCreate(&stream);
    rppfftSetStream(rppfftForwrdHandle, stream);

    gettimeofday(&tv0,&tz);
    rppfftExecC2C(rppfftForwrdHandle, device_in, device_out, direction);
    rtStreamSynchronize(stream);
    gettimeofday(&tv1,&tz);

    if(fastAlgo)
    {
        // SRamManager: convert fast-path output format and upload back to DDR.
        smgr.ReformatInPlace(device_out);
        //smgr.ReformatOutPlace(device_out);
        smgr.Upload(device_out);
    }

    assert(rtSuccess == rtMemcpy(host_out, device_out,  length * batch * sizeof(rppfftComplex), rtMemcpyDeviceToHost));

    rppfftComplex* expected;
    assert(rtSuccess == rtMallocHost((void**)&expected, length * batch * sizeof(rppfftComplex)));
    gettimeofday(&tv2,&tz);
    fft1d_cpu(host_in, expected, batch, length, direction, isShift, columnFft);
    gettimeofday(&tv3,&tz);

    float mse;
    bool isPass = VerifyOutput(host_out, expected, length * batch, mse);

    smgr.Free(device_in);
    smgr.Free(device_out);
    smgr.Clear();
    rtStreamDestroy(stream);
    rppfftDestroy(rppfftForwrdHandle);


    tm0 = (tv0.tv_sec*1000000 + tv0.tv_usec);
    tm1 = (tv1.tv_sec*1000000 + tv1.tv_usec);
    tm2 = (tv2.tv_sec*1000000 + tv2.tv_usec);
    tm3 = (tv3.tv_sec*1000000 + tv3.tv_usec);   
    if(isPass)
    {
        printf("FFT 1d Passed! columnFft:%4d, Batch:%6d, FFT Size:%6d, Device Run:%8dus, CPU Run:%8dus\n",
               (int)columnFft, batch, length, (uint32_t)(tm1 - tm0), (uint32_t)(tm3 - tm2));
    }
    else
    {
        printf("FFT 1d Failed! columnFft:%4d, Batch:%6d, FFT Size:%6d, Device Run:%8dus, CPU Run:%8dus\n",
               (int)columnFft, batch, length, (uint32_t)(tm1 - tm0), (uint32_t)(tm3 - tm2));
        printf("MSE = %.8f\n", mse);
        printFirstInputOutputValues1D("[FFT 1D]", host_in, host_out, batch, length, columnFft);
        assert(false);
    }
    printf("MSE = %.8f\n", mse);
    printFirstInputOutputValues1D("[FFT 1D]", host_in, host_out, batch, length, columnFft);
    printf("[DEMO END] FFT 1D | columnFft=%d\n", (int)columnFft);
    printf("============================================================\n");
   rtFreeHost(host_in);
   rtFreeHost(host_out);
   rtFreeHost(expected);
   rtFree(device_in);
   rtFree(device_out);
}
/**
 * @brief Run one 2D FFT case on RPP and verify against CPU reference.
 * @param height Matrix height.
 * @param width Matrix width.
 * @param direction Transform direction.
 * @param columnFft Input-generation mode switch for demo comparison.
 * @param fastAlgo Whether fast SRAM path is enabled.
 * @param runtimeIo Whether plan uses runtime I/O mode.
 */
static void runTest2d(int height, int width, int direction, bool columnFft, bool fastAlgo, bool runtimeIo)
{
    printf("\n============================================================\n");
    printf("[DEMO START] FFT 2D | columnFft=%d | height=%d | width=%d\n",
           (int)columnFft, height, width);
    printf("============================================================\n");

    rtError_t err = rtSuccess;
    rppfftResult ret;
    rppfftHandle rppfftForwrdHandle; rtStream_t stream;
    struct timezone tz; struct timeval tv0; struct timeval tv1; struct timeval tv2; struct timeval tv3;
    uint64_t tm0, tm1;
    int length = width;
    int size = length * height * sizeof(rppfftComplex);
    rppfftComplex* host_in, *host_out, *device_in, *device_out;
    rppsmgr::SRamManager& smgr = rppsmgr::SRamManager::GetInstance();

    assert(rtSuccess == rtMallocHost((void**)&host_in, size));
    assert(rtSuccess == rtMallocHost((void**)&host_out, size));

    generateInput(host_in, height, width, columnFft);

    assert(rtSuccess == rtMalloc((void**)&device_in,  size));
    assert(rtSuccess == rtMalloc((void**)&device_out,  size));
    // rtMemcpy: host -> device DDR input copy.
    assert(rtSuccess == rtMemcpy(device_in, host_in,  size, rtMemcpyHostToDevice));


    if(fastAlgo)
    {
        //fast algo only support fft size < 512K
        assert(height * width <= FAST_FFT_SIZE);
        // SRamManager: register fast-path SRAM mappings and prepare input format.
        smgr.Allocate(device_in, height, length, sizeof(rppfftComplex),HCFMT);
        smgr.Allocate(device_out, height, length, sizeof(rppfftComplex), RCFMT);
        smgr.Download(device_in);
        smgr.ReformatInPlace(device_in);
        if(runtimeIo)
            // rppfftPlan2d: build plan in runtime I/O mode.
            ret = rppfftPlan2d(&rppfftForwrdHandle, height, width, RPPFFT_C2C, fastAlgo);
        else
            // rppfftPlan2d: build plan in fixed I/O mode.
            ret = rppfftPlan2d(&rppfftForwrdHandle, height, width, RPPFFT_C2C, fastAlgo, device_in, device_out, direction);
    }
    else
    {
        if(runtimeIo)
            ret = rppfftPlan2d(&rppfftForwrdHandle, height, width, RPPFFT_C2C, fastAlgo);
        else
            ret = rppfftPlan2d(&rppfftForwrdHandle, height, width, RPPFFT_C2C, fastAlgo, device_in, device_out, direction);
    }
    
    assert(ret == RPPFFT_SUCCESS);
    // rppfftSetStream: bind FFT execution to this stream.
    rtStreamCreate(&stream);
    rppfftSetStream(rppfftForwrdHandle, stream);


    gettimeofday(&tv0,&tz);
    rppfftExecC2C(rppfftForwrdHandle, device_in, device_out, direction);
    rtStreamSynchronize(stream);
    gettimeofday(&tv1,&tz);
    if(fastAlgo)
    {
        // SRamManager: convert fast-path output format and upload back to DDR.
        smgr.ReformatInPlace(device_out);
        smgr.Upload(device_out);
    }
    
    assert(rtSuccess == rtMemcpy(host_out, device_out,  width * height * sizeof(rppfftComplex), rtMemcpyDeviceToHost));
    
    rppfftComplex* expected;
    assert(rtSuccess == rtMallocHost((void**)&expected, width * height * sizeof(rppfftComplex)));

    fft2d_cpu(host_in, expected, height, width, direction);

    float mse;
    bool isPass = VerifyOutput(host_out, expected, height * width, mse);

    smgr.Free(device_in);
    smgr.Free(device_out);
    smgr.Clear();
    rtStreamDestroy(stream);
    rppfftDestroy(rppfftForwrdHandle);


    tm0 = (tv0.tv_sec*1000000 + tv0.tv_usec);
    tm1 = (tv1.tv_sec*1000000 + tv1.tv_usec);
    if(isPass)
    {
        printf("FFT 2d Passed! columnFft:%4d, height:%6d, width:%6d, Device Run:%8dus\n",
               (int)columnFft, height, width, (uint32_t)(tm1 - tm0));
    }
    else
    {
        printf("FFT 2d Failed! columnFft:%4d, height:%6d, width:%6d, Device Run:%8dus\n",
               (int)columnFft, height, width, (uint32_t)(tm1 - tm0));
        printf("MSE = %.8f\n", mse);
        printFirstInputOutputValues2D("[FFT 2D]", host_in, host_out, height, width);
        assert(false);
    }
    printf("MSE = %.8f\n", mse);
    printFirstInputOutputValues2D("[FFT 2D]", host_in, host_out, height, width);
    printf("[DEMO END] FFT 2D | columnFft=%d\n", (int)columnFft);
    printf("============================================================\n");
    rtFreeHost(host_in);
    rtFreeHost(host_out);
    rtFreeHost(expected);
    rtFree(device_in);
    rtFree(device_out);
}

/**
 * @brief Demo entry point: initialize SRAM manager and run default 1D/2D FFT cases.
 * @param argc Command-line argument count (unused in current default flow).
 * @param argv Command-line argument values (unused in current default flow).
 * @return 0 on success.
 */
int main() {
    rppsmgr::SRamManager& smgr = rppsmgr::SRamManager::GetInstance();
    // SRamManager Init: create workspace for FFT fast path.
    smgr.Init(SRAM_WORK_SPACE);

    bool isShift, fastAlgo, runtimeIo;
    int height, width;
    int batch = 32;
    int fftSize = 32;

    isShift = false;
    fastAlgo = true;
    runtimeIo = false;

    // 1D demos: run both columnFft modes with batch=32, fftSize=32.
    runTest1d(batch, fftSize, RPPFFT_FORWARD, isShift, false, fastAlgo, runtimeIo);
    runTest1d(batch, fftSize, RPPFFT_FORWARD, isShift, true, fastAlgo, runtimeIo);

    // 2D demos: run both columnFft modes with height=32, width=32.
    height = 32;
    width = 32;
    runTest2d(height, width, RPPFFT_FORWARD, false, fastAlgo, runtimeIo);
    runTest2d(height, width, RPPFFT_FORWARD, true, fastAlgo, runtimeIo);

    // SRamManager Destroy: release workspace before exit.
    smgr.Destroy();
    return 0;

}
