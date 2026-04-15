# rpp_fft_perf_boost

This module is a customer-facing FFT performance demo that compares two RPP 1D FFT configurations and reports speedup.

## Hardware and Runtime Context

- Main headers used in this demo:
  - `rppfft.h`
  - `rpp_runtime.h`
  - `rpp_smgr.h`
  - `rpp_drv_api.h`
- Memory model used:
  - Host memory: `rtMallocHost` / `rtFreeHost`
  - Device DDR: `rtMalloc` / `rtFree`
  - SRAM fast path: managed via `rppsmgr::SRamManager`
- Main API groups:
  - FFT plan/exec: `rppfftPlan1d`, `rppfftExecC2C`, `rppfftSetStream`, `rppfftDestroy`
  - Data movement: `rtMemcpy(..., rtMemcpyHostToDevice)`, `rtMemcpy(..., rtMemcpyDeviceToHost)`
  - SRAM fast path: `smgr.Allocate`, `smgr.Download`, `smgr.ReformatInPlace`, `smgr.Upload`

## Workflow (High Level)

1. Initialize SRAM manager workspace.
2. Run baseline case:
   - `fastAlgo=false`, `columnFft=false`, runtime I/O
3. Run optimized case:
   - `fastAlgo=true`, `columnFft=true`, fixed I/O
4. For each case:
   - Allocate host/device buffers and generate deterministic input
   - Build FFT plan and bind stream
   - Warm up then run measured FFT iterations
   - Copy output to host and print sample values
5. Print summary and compute speedup (`baseline / optimized`).
6. Destroy SRAM manager and release resources.

## Workflow Diagram

```text
+----------------------------------+
| main()                           |
| smgr.Init(SRAM_WORK_SPACE)       |
+----------------+-----------------+
                 |
                 v
+----------------------------------+
| run_perf_case(baseline)          |
| fast=false, columnFft=false,     |
| runtime I/O                      |
+----------------+-----------------+
                 |
                 v
+----------------------------------+
| run_perf_case(optimized)         |
| fast=true, columnFft=true,       |
| fixed I/O                        |
+----------------+-----------------+
                 |
                 v
+----------------------------------+
| print avg time + speedup summary |
+----------------+-----------------+
                 |
                 v
+----------------------------------+
| smgr.Destroy() + cleanup         |
+----------------------------------+
```

## Cases Compared

Both cases use:

- `batch = 1024`
- `fft_size = 256`
- `warmup_iters = 20`
- `measure_iters = 200`

Case definitions:

1. Baseline:
   - normal mode (`fastAlgo=false`)
   - `columnFft=false`
   - runtime I/O
2. Optimized:
   - fast mode (`fastAlgo=true`)
   - `columnFft=true`
   - fixed I/O

## Measured Performance

| Case | Config | Avg Device Time (us / iter) |
|---|---|---:|
| Baseline | `fastAlgo=false`, `columnFft=false`, `runtimeIo=true` | `844.610` |
| Optimized | `fastAlgo=true`, `columnFft=true`, `runtimeIo=false` | `244.425` |

Computed speedup:

- `speedup = 844.610 / 244.425 = 3.455x`

Expected range note (for customer slides):

- For this tested shape (`batch=1024`, `fft_size=256`), a speedup around `3x` or higher is a reasonable expectation with `fastAlgo + columnFft=true + Fixed I/O`.
- Actual speedup may vary with system load, runtime environment, and FFT shape configuration.

## Build and Run

From `rpp_fft_perf_boost`:

```bash
mkdir -p build
cd build
cmake ..
make -j
./rpp_fft_perf_boost
```

## Notes

- Fast mode requires SRAM workspace initialization via `smgr.Init(SRAM_WORK_SPACE)`.
- Fast mode requires FFT size constraint check (`batch * fft_size <= FAST_FFT_SIZE`).
- The measured time is FFT execution pipeline time (warmup excluded), suitable for mode-to-mode comparison.
