# rpp_manual_sram

This module demonstrates a manual SRAM workflow on RPP hardware. It computes `C = A + B` and explicitly controls all memory movement between host memory, device DDR, and on-card SRAM.

## Hardware and Runtime Context

- Target runtime headers used in this module: `rpp_runtime.h`, `rpp_drv_api.h`, `rpp_com.h`
- Memory types used:
  - Host memory: `malloc` / `free`
  - Device (DDR) memory on the RPP card: `rtMalloc` / `rtFree`
  - On-card SRAM: `rtMallocSram` / `rtFreeSram`
- Data movement APIs used in this code:
  - Host -> device DDR: `rtMemcpy(..., rtMemcpyHostToDevice)`
  - Device DDR -> SRAM: `rtMemcpy(..., rtMemcpyDeviceToSram)`
  - SRAM -> device DDR: `rtMemcpy(..., rtMemcpySramToDevice)`
  - Device DDR -> host: `rtMemcpy(..., rtMemcpyDeviceToHost)`

## Workflow (High Level)

1. Allocate and initialize host buffers `h_A`, `h_B`, `h_C`.
2. Allocate device DDR buffers `d_A`, `d_B`, `d_C` using `rtMalloc`.
3. Allocate SRAM buffers `sram_A`, `sram_B`, `sram_C` using `rtMallocSram`.
4. Copy input matrices from host to device DDR.
5. Copy inputs from device DDR to SRAM.
6. Launch `hello_world_add_manual` on SRAM pointers.
7. Copy result from SRAM to device DDR.
8. Copy result from device DDR to host and print timing/output.
9. Free SRAM buffers, device DDR buffers, and host buffers.

## Workflow (ASCII Diagram)

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
+-------------------------------+
| rtMallocSram(sram_A/B/C)      |
| allocate manual SRAM buffers  |
+---------------+---------------+
                |
                v
+----------------------------------+
| rtMemcpy H2D for A/B             |
| host -> device DDR               |
+----------------+-----------------+
                 |
                 v
+----------------------------------+
| rtMemcpy DeviceToSram for A/B    |
| device DDR -> SRAM               |
+----------------+-----------------+
                 |
                 v
+----------------------------------+
| hello_world_add_manual kernel    |
| read/write SRAM pointers         |
+----------------+-----------------+
                 |
                 v
+----------------------------------+
| rtMemcpy SramToDevice for C      |
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
| print timing/output + cleanup    |
+----------------------------------+
```

## Build and Run

From `rpp_manual_sram`:

```bash
mkdir -p build
cd build
cmake ..
make -j
./rpp_manual_sram
```

The output includes transfer/kernel timing, launch configuration, sample values, and final status.
