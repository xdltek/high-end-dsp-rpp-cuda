# high-end-dsp-rpp-cuda

![XDL Logo](images/logo_color_horizontal.png)

`high-end-dsp-rpp-cuda` is a customer-facing learning and reference repository for building high-performance DSP applications with the RPP CUDA toolchain.

It combines programming guides, API compatibility notes, and runnable examples so users can move from first program to optimized production-style kernels. Typical workloads include FFT, transpose, FIR, and other compute-intensive signal/data processing pipelines.

## Introduction

This repository is designed to answer one practical question:

**How do we write, validate, and optimize RPP CUDA programs for real DSP workloads?**

To solve that, the content is organized in three layers:

- **Programming foundations**: memory model, data movement, stream/event flow, and SRAM usage.
- **API understanding**: compatibility details and usage patterns for RPP runtime and libraries.
- **Performance-oriented examples**: baseline vs optimized demos (e.g., fast mode, fixed I/O, format-aware data flow).

## Repository Structure

- `xdl_cuda_programming`
  - Core CUDA programming guide for RPP devices.
  - Includes starter and progressive demos:
    - `rpp_first_demo`
    - `rpp_manual_sram`
    - `rpp_pingpong`
    - `rpp_tile_based`

- `xdl_rpp_cuda_compatibility`
  - Compatibility and integration guidance for project setup and SRAM APIs.
  - Includes bilingual guide materials for CMake and SRAM API usage.

- `rpp_fft_api_and_usage`
  - FFT-focused API guide and runnable examples:
    - `rpp_fft_v4`
    - `rpp_fft_perf_boost`
    - `rpp_fft_perf_boost_2d`
  - Demonstrates correctness checks and performance tuning techniques.

## What You Can Learn

- Build and run RPP CUDA projects with clean CMake organization.
- Manage Host / Device DDR / SRAM memory paths correctly.
- Implement asynchronous pipelines with streams and events.
- Use FFT APIs in both baseline and accelerated configurations.
- Measure speedup and explain optimization impact to customers.

## Recommended Learning Path

1. Start with `xdl_cuda_programming` basic demos.
2. Read `xdl_rpp_cuda_compatibility` for setup and API behavior details.
3. Move to `rpp_fft_api_and_usage` for end-to-end DSP examples and performance tuning.

## Target Audience

- DSP algorithm engineers onboarding to RPP CUDA.
- Application engineers building customer-facing acceleration demos.
- Performance engineers who need reproducible optimization patterns.
