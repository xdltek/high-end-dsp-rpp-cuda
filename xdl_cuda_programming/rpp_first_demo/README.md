# rpp_first_demo

**[Back to Home](../../README.md)**

This module is the first RPP learning demo. It runs a simple matrix add kernel (`C = A + B`) while showing the full RPP data path from host memory to device DDR, then SRAM, and back.

## Hardware and Runtime Context

- Target runtime headers in this module: `rpp_runtime.h`, `rpp_drv_api.h`, `rpp_smgr.h`, `rpp_block_segment.h`, `rpp_com.h`
- Memory types used:
  - Host memory: `malloc` / `free`
  - Device (DDR) memory on the RPP card: `rtMalloc` / `rtFree`
  - On-card SRAM managed by `rppsmgr::SRamManager`
- Data movement APIs used in this code:
  - Host -> device DDR: `rtMemcpy(..., rtMemcpyHostToDevice)`
  - Device DDR -> SRAM: `smgr.Download(...)`
  - SRAM -> device DDR: `smgr.Upload(...)`
  - Device DDR -> host: `rtMemcpy(..., rtMemcpyDeviceToHost)`

## Workflow (High Level)

1. Allocate and initialize host buffers `h_A`, `h_B`, `h_C`.
2. Allocate device DDR buffers `d_A`, `d_B`, `d_C` with `rtMalloc`.
3. Initialize `SRamManager` and register pitched layouts with `smgr.PitchAllocate`.
4. Copy input data from host to device DDR with `rtMemcpy`.
5. Move inputs from device DDR to SRAM with `smgr.Download`.
6. Launch `hello_world_add` using SRAM addresses from `smgr.GetSRamAddr`.
7. Move result from SRAM to device DDR with `smgr.Upload`.
8. Copy result from device DDR to host and print sample values.
9. Destroy manager and free host/device resources.

## Workflow ASCII Diagram

```text
+-------------------------+
| main()                  |
| allocate/init host data |
+------------+------------+
             |
             v
+-------------------------------+
| rtMalloc(d_A, d_B, d_C)       |
| allocate device DDR buffers   |
+---------------+---------------+
                |
                v
+----------------------------------------------+
| smgr.Init + smgr.PitchAllocate(A/B/C)        |
| create SRAM workspace and DDR<->SRAM mapping |
+----------------+-----------------------------+
                 |
                 v
+----------------------------------+
| rtMemcpy H2D for A/B             |
| host -> device DDR               |
+----------------+-----------------+
                 |
                 v
+----------------------------------+
| smgr.Download(d_A, d_B)          |
| device DDR -> SRAM               |
+----------------+-----------------+
                 |
                 v
+----------------------------------+
| hello_world_add kernel           |
| read/write SRAM pointers         |
+----------------+-----------------+
                 |
                 v
+----------------------------------+
| smgr.Upload(d_C)                 |
| SRAM -> device DDR               |
+----------------+-----------------+
                 |
                 v
+----------------------------------+
| rtMemcpy D2H for C               |
| device DDR -> host               |
+----------------+-----------------+
                 |
                 v
+----------------------------------+
| print result + cleanup           |
+----------------------------------+
```

## Build and Run

From `rpp_first_demo`:

```bash
mkdir -p build
cd build
cmake ..
make rpp_first_demo -j
./rpp_first_demo
```

The program prints launch configuration, the first output values, and a success status message.
