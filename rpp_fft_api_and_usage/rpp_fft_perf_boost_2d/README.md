# rpp_fft_perf_boost_2d

**[Back to Home](../../README.md)**

This module is a customer-facing 2D FFT performance demo that compares baseline mode and optimized mode on the same matrix shape.

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
  - FFT plan/exec: `rppfftPlan2d`, `rppfftExecC2C`, `rppfftSetStream`, `rppfftDestroy`
  - Data movement: `rtMemcpy(..., rtMemcpyHostToDevice)`, `rtMemcpy(..., rtMemcpyDeviceToHost)`
  - SRAM fast path: `smgr.Allocate`, `smgr.Download`, `smgr.ReformatInPlace`, `smgr.Upload`

## Workflow (High Level)

1. Initialize SRAM manager workspace.
2. Run baseline case:
   - `fastAlgo=false`, runtime I/O
3. Run optimized case:
   - `fastAlgo=true`, fixed I/O
4. For each case:
   - Allocate host/device buffers and generate deterministic 2D input
   - Build 2D FFT plan and bind stream
   - Warm up then run measured iterations
   - Copy output to host and print sample values
5. Print speedup summary (`baseline / optimized`).
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
| run_perf_case_2d(baseline)       |
| fast=false, runtime I/O          |
+----------------+-----------------+
                 |
                 v
+----------------------------------+
| run_perf_case_2d(optimized)      |
| fast=true, fixed I/O             |
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

- `height = 1024`
- `width = 128`
- `warmup_iters = 20`
- `measure_iters = 200`

Case definitions:

1. Baseline:
   - normal mode (`fastAlgo=false`)
   - runtime I/O
2. Optimized:
   - fast mode (`fastAlgo=true`)
   - fixed I/O

## Measured Performance

| Case | Config | Avg Device Time (us / iter) |
|---|---|---:|
| Baseline | `fastAlgo=false`, `runtimeIo=true` | `1276.250` |
| Optimized | `fastAlgo=true`, `runtimeIo=false` | `808.240` |

Computed speedup:

- `speedup = 1276.250 / 808.240 = 1.579x`

Expected range note (for customer slides):

- For this tested shape (`height=1024`, `width=128`), a speedup around `1.5x` or higher is a reasonable expectation with `fastAlgo + Fixed I/O`.
- Actual speedup may vary with system load, runtime environment, and FFT shape configuration.

## Build and Run

From `rpp_fft_perf_boost_2d`:

```bash
mkdir -p build
cd build
cmake ..
make -j
./rpp_fft_perf_boost_2d
```

## Notes

- Fast mode requires SRAM workspace initialization (`smgr.Init(SRAM_WORK_SPACE)`).
- Fast mode requires size check (`height * width <= FAST_FFT_SIZE`).
- The measured time is FFT execution pipeline time (warmup excluded), suitable for mode-to-mode comparison.
