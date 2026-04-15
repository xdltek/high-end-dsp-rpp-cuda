# high-end-dsp-rpp-cuda

![XDL Logo](images/logo_color_horizontal.png)

`high-end-dsp-rpp-cuda` is a customer-facing learning and reference repository for building high-performance DSP applications with the RPP CUDA toolchain.

It combines programming guides, compatibility notes, and runnable examples so users can move from first program to optimized production-style kernels. Typical workloads include matrix-style data movement, SRAM-managed compute, and FFT acceleration.

## Hardware and Runtime Context

- RPP in this repository refers to an accelerator card runtime, not NVIDIA CUDA runtime behavior on a standard GPU.
- Memory terms used across the examples:
  - Host: CPU memory allocated with APIs such as `malloc` or `rtMallocHost`
  - Device DDR: card global memory allocated with `rtMalloc`
  - SRAM: small fast on-card memory managed either manually (`rtMallocSram`) or through `rppsmgr::SRamManager`
- Data movement patterns used across the demos:
  - Host -> device DDR: `rtMemcpy(..., rtMemcpyHostToDevice)` or `rppMemcpyHtoDAsync`
  - Device DDR -> SRAM: `rtMemcpy(..., rtMemcpyDeviceToSram)`, `rppMemcpyDtoSAsync`, or `smgr.Download`
  - SRAM -> device DDR: `rtMemcpy(..., rtMemcpySramToDevice)`, `rppMemcpyStoDAsync`, or `smgr.Upload`
  - Device DDR -> host: `rtMemcpy(..., rtMemcpyDeviceToHost)` or `rppMemcpyDtoHAsync`

## Repository Structure

- `xdl_cuda_programming`
  - Programming-focused learning modules for SRAM usage, asynchronous streams, ping-pong execution, and tile-based processing.
  - Module workflow docs:
    - [rpp_first_demo](xdl_cuda_programming/rpp_first_demo/README.md)
    - [rpp_manual_sram](xdl_cuda_programming/rpp_manual_sram/README.md)
    - [rpp_pingpong](xdl_cuda_programming/rpp_pingpong/README.md)
    - [rpp_tile_based](xdl_cuda_programming/rpp_tile_based/README.md)

- `rpp_fft_api_and_usage`
  - FFT-focused demos covering correctness validation, fixed I/O, fast mode, and performance comparison.
  - Module workflow docs:
    - [rpp_fft_v4](rpp_fft_api_and_usage/rpp_fft_v4/README.md)
    - [rpp_fft_perf_boost](rpp_fft_api_and_usage/rpp_fft_perf_boost/README.md)
    - [rpp_fft_perf_boost_2d](rpp_fft_api_and_usage/rpp_fft_perf_boost_2d/README.md)

- `docs`
  - GitHub Pages entry and browser-friendly copies of the customer PDF guides.

## Workflow (High Level)

1. Read the PDF guides in `docs/pdfs` or through GitHub Pages for API background and customer training material.
2. Start with `xdl_cuda_programming` to learn the basic Host -> device DDR -> SRAM -> kernel -> result flow.
3. Move to async and pipeline-style demos (`rpp_pingpong`, `rpp_tile_based`) to understand stream/event coordination.
4. Continue with `rpp_fft_api_and_usage` to study FFT planning, execution, verification, and performance tuning.
5. Use the module README in each example directory as the main workflow reference before reading the source.

## Workflow Diagram

```text
+--------------------------------------+
| PDF guides / GitHub Pages docs       |
| programming + API background         |
+-------------------+------------------+
                    |
                    v
+--------------------------------------+
| xdl_cuda_programming                 |
| first demo -> manual SRAM -> async   |
| ping-pong -> tile-based pipeline     |
+-------------------+------------------+
                    |
                    v
+--------------------------------------+
| rpp_fft_api_and_usage                |
| correctness demos -> perf demos      |
| 1D / 2D FFT optimization patterns    |
+-------------------+------------------+
                    |
                    v
+--------------------------------------+
| customer-ready understanding         |
| build, validate, measure, explain    |
+--------------------------------------+
```

## Summary Table

| Area | Main Content | Purpose |
|---|---|---|
| Programming foundations | `xdl_cuda_programming` | Learn memory hierarchy, SRAM usage, and async execution flow |
| FFT API usage | `rpp_fft_api_and_usage` | Learn plan creation, execution, correctness checks, and optimization |
| Customer documents | `docs/pdfs` and GitHub Pages | Open the official PDF guides in the browser or download them |

## Documentation

These links work from the repository itself. The PDF links use `?raw=1` so GitHub opens the file content directly instead of sending users to the blob/code renderer page.

### Repository Documentation

- [Documentation Home](docs/index.md)

### XDL CUDA Programming

- [XDL CUDA Programming Guide (EN)](docs/pdfs/xdl-cuda-programming-guide-en.pdf?raw=1)
- [XDL CUDA Programming Guide (CN)](docs/pdfs/xdl-cuda-programming-guide-cn.pdf?raw=1)

### RPP CUDA Compatibility PDFs

- [XDL RPP CMakeLists Writing Guide (EN)](docs/pdfs/xdl-rpp-cmakelists-writing-guide-en.pdf?raw=1)
- [XDL RPP SRAM API Introduction (EN)](docs/pdfs/xdl-rpp-sram-api-introduction-en.pdf?raw=1)
- [XDL RPP CMakeLists Writing Guide (CN)](docs/pdfs/xdl-rpp-cmakelists-writing-guide-cn.pdf?raw=1)
- [XDL RPP SRAM API Guide (CN)](docs/pdfs/xdl-rpp-sram-api-guide-cn.pdf?raw=1)

### RPP FFT API And Usage

- [XDL RPP FFT API Introduction (EN)](docs/pdfs/xdl-rpp-fft-api-introduction-en.pdf?raw=1)
- [XDL RPP FFT API Guide (CN)](docs/pdfs/xdl-rpp-fft-api-guide-cn.pdf?raw=1)

### Future GitHub Pages URL

- `https://xdltek.github.io/high-end-dsp-rpp-cuda/`

## Build and Run

All the examples use the same workflow from inside the module directory:

```bash
mkdir -p build
cd build
cmake ..
make -j
./<example_name>
```

Examples:

- `xdl_cuda_programming/rpp_first_demo`
- `xdl_cuda_programming/rpp_manual_sram`
- `xdl_cuda_programming/rpp_pingpong`
- `xdl_cuda_programming/rpp_tile_based`
- `rpp_fft_api_and_usage/rpp_fft_v4`
- `rpp_fft_api_and_usage/rpp_fft_perf_boost`
- `rpp_fft_api_and_usage/rpp_fft_perf_boost_2d`

## Recommended Learning Path

1. Start with `rpp_first_demo` to understand the minimal memory and launch flow.
2. Read `rpp_manual_sram` to see explicit SRAM allocation and transfer control.
3. Study `rpp_pingpong` and `rpp_tile_based` for stream/event-driven pipelines.
4. Continue with `rpp_fft_v4` for correctness and validation flow.
5. Finish with `rpp_fft_perf_boost` and `rpp_fft_perf_boost_2d` for customer-facing optimization comparisons.

## Target Audience

- DSP algorithm engineers onboarding to RPP CUDA
- Application engineers building customer-facing acceleration demos
- Performance engineers who need reproducible optimization patterns
