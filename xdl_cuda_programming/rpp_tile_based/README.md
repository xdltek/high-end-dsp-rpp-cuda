# rpp_tile_based

This module demonstrates tile-based ping-pong processing on RPP hardware. It computes tiled `C = A + B` by alternating two SRAM slots (`slot0`, `slot1`) and coordinating transfer and compute with asynchronous streams plus events.

## Hardware and Runtime Context

- Target runtime headers used in this module: `rpp_runtime.h`, `rpp_drv_api.h`, `rpp_com.h`
- Memory types used:
  - Host memory: `malloc` / `free`
  - Device (DDR) memory on the RPP card: `rtMalloc` / `rtFree`
  - On-card SRAM tile buffers: `rtMallocSram` / `rtFreeSram`
- Stream/event and transfer APIs used:
  - Stream APIs: `rppStreamCreate`, `rppStreamSynchronize`, `rppStreamWaitEvent`, `rppStreamDestroy`
  - Event APIs: `rppEventCreate`, `rppEventRecord`, `rppEventDestroy`
  - Host -> device DDR: `rppMemcpyHtoDAsync`
  - Device DDR -> SRAM tile: `rppMemcpyDtoSAsync`
  - SRAM tile -> device DDR: `rppMemcpyStoDAsync`
  - Device DDR -> host: `rppMemcpyDtoHAsync`

## Workflow (High Level)

1. Define matrix size and tile size (`tile_height`, `tile_count`, `tile_bytes`).
2. Allocate host buffers and initialize input values.
3. Allocate full-size device DDR buffers (`d_A`, `d_B`, `d_C`).
4. Allocate ping-pong SRAM tile buffers for A/B/C (`[0]` and `[1]` slots).
5. Create transfer/compute streams and per-slot load/compute events.
6. Copy full A/B from host to device DDR.
7. Preload tile 0 to SRAM slot0, then process all tiles in a loop:
   - wait for tile load event
   - launch tile compute on current slot
   - preload next tile to alternate slot
   - wait for compute event and store current output tile back to device DDR
8. Synchronize streams, copy full `d_C` back to host, print timing and sample values.
9. Destroy streams/events and free SRAM/device/host memory.

## Workflow Diagram

```text
+-----------------------------+
| main()                      |
| setup matrix/tile metadata  |
+-------------+---------------+
              |
              v
+-------------------------------------+
| allocate host + device DDR + SRAM   |
| d_A/d_B/d_C + A/B/C slot0/slot1     |
+----------------+--------------------+
                 |
                 v
+-------------------------------------+
| create streams/events               |
| transfer_stream + compute_stream    |
+----------------+--------------------+
                 |
                 v
+-------------------------------------+
| rppMemcpyHtoDAsync (full A/B)       |
| host -> device DDR                  |
+----------------+--------------------+
                 |
                 v
+-------------------------------------+
| preload tile0 to slot0 (DtoS)       |
| record load_done[0]                 |
+----------------+--------------------+
                 |
                 v
+-------------------------------------+
| tile loop (tile = 0..tile_count-1)  |
| wait load_done[current]             |
| kernel on current slot              |
| record compute_done[current]        |
| preload next tile to next slot      |
| wait compute_done[current]          |
| store current output tile (StoD)    |
+----------------+--------------------+
                 |
                 v
+-------------------------------------+
| rppMemcpyDtoHAsync (full C)         |
| device DDR -> host                  |
+----------------+--------------------+
                 |
                 v
+-------------------------------------+
| print timeline/schedule + cleanup   |
+-------------------------------------+
```

## Build and Run

From `rpp_tile_based`:

```bash
mkdir -p build
cd build
cmake ..
make -j
./rpp_tile_based
```

The program prints pipeline timing, tile schedule, launch configuration, sample output values, and final status.
