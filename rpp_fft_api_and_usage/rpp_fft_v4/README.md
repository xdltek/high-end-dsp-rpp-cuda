# rpp_fft_v4

**[Back to Home](../../README.md)**

This module is an RPP FFT demo that runs 1D and 2D C2C FFT cases on device, compares results with CPU reference implementations, and reports timing plus MSE.

## Hardware and Runtime Context

- Main headers used in this demo:
  - `rppfft.h`
  - `rpp_runtime.h`
  - `rpp_smgr.h`
  - `rpp_drv_api.h`
- Memory model used:
  - Host memory: `rtMallocHost` / `rtFreeHost`
  - Device DDR: `rtMalloc` / `rtFree`
  - SRAM fast path (optional): managed via `rppsmgr::SRamManager`
- Main API groups:
  - FFT plan/exec: `rppfftPlan1d`, `rppfftPlan2d`, `rppfftExecC2C`, `rppfftSetStream`, `rppfftDestroy`
  - Data movement: `rtMemcpy(..., rtMemcpyHostToDevice)` and `rtMemcpy(..., rtMemcpyDeviceToHost)`
  - Fast path SRAM flow: `smgr.Allocate`, `smgr.Download`, `smgr.ReformatInPlace`, `smgr.Upload`

## Workflow (High Level)

1. Initialize SRAM manager workspace for FFT fast path.
2. Run 1D FFT demo cases with `columnFft=false` and `columnFft=true`.
3. Run 2D FFT demo cases with `columnFft=false` and `columnFft=true`.
4. For each case:
   - Allocate host/device buffers
   - Fill deterministic input
   - Build FFT plan (`runtime I/O` or `fixed I/O`)
   - Execute `rppfftExecC2C` on stream
   - Copy output back to host
   - Run CPU reference FFT
   - Compute MSE and print pass/fail
   - Print first 64 input/output pairs
5. Destroy SRAM manager and release resources.

## Workflow Diagram

```text
+------------------------------+
| main()                       |
| init SRamManager workspace   |
+---------------+--------------+
                |
                v
+------------------------------+
| runTest1d / runTest2d        |
| (columnFft false/true cases) |
+---------------+--------------+
                |
                v
+--------------------------------------+
| allocate host/device buffers         |
| generateInput                        |
+----------------+---------------------+
                 |
                 v
+--------------------------------------+
| optional fast path (SRAM)            |
| smgr.Allocate/Download/Reformat      |
+----------------+---------------------+
                 |
                 v
+--------------------------------------+
| rppfftPlan1d/2d + rppfftSetStream    |
| rppfftExecC2C                        |
+----------------+---------------------+
                 |
                 v
+--------------------------------------+
| optional fast output path            |
| smgr.ReformatInPlace + smgr.Upload   |
+----------------+---------------------+
                 |
                 v
+--------------------------------------+
| copy output to host                  |
| CPU reference FFT                    |
| VerifyOutput (MSE)                   |
| print first 64 input/output pairs    |
+----------------+---------------------+
                 |
                 v
+--------------------------------------+
| cleanup and next case                |
+--------------------------------------+
```

## Build and Run

From `rpp_fft_v4`:

```bash
mkdir -p build
cd build
cmake ..
make -j
./rpp_fft_v4
```

The program prints per-demo section markers, pass/fail status, MSE, timing, and the first 64 input/output values.
