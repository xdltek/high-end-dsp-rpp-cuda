# rpp_pingpong

This module demonstrates an advanced RPP workflow with ping-pong SRAM buffers and asynchronous transfer/compute coordination. It evaluates:

`C = ((A + B) * B) + B`

using two runs (cold and warm) and reports transfer plus per-stage compute timing.

## Hardware and Runtime Context

- Target runtime headers used in this module: `rpp_runtime.h`, `rpp_drv_api.h`, `rpp_com.h`
- Memory types used:
  - Host memory: `malloc` / `free`
  - Device (DDR) memory on the RPP card: `rtMalloc` / `rtFree`
  - On-card SRAM: `rtMallocSram` / `rtFreeSram`
- Stream/event and transfer APIs used in `this code:
  - Stream APIs: `rppStreamCreate`, `rppStreamSynchronize`, `rppStreamWaitEvent`, `rppStreamDestroy`
  - Event APIs: `rppEventCreate`, `rppEventRecord`, `rppEventDestroy`
  - Host -> device DDR: `rppMemcpyHtoDAsync`
  - Device DDR -> SRAM: `rppMemcpyDtoSAsync`
  - SRAM -> device DDR: `rppMemcpyStoDAsync`
  - Device DDR -> host: `rppMemcpyDtoHAsync`

## Workflow (High Level)

1. Allocate and initialize host buffers.
2. Allocate device DDR buffers and SRAM buffers (`ping0`, `ping1`, `sram_B`).
3. Create `transfer_stream`, `compute_stream`, and dependency events.
4. Copy A/B from host to device DDR, then from device DDR to SRAM (`ping0`, `sram_B`).
5. Run cold ping-pong compute sequence on compute stream: `Add -> Mul -> Add`.
6. Reload A into `ping0`, then run warm ping-pong compute sequence.
7. Copy final result (`ping1`) from SRAM to device DDR, then to host.
8. Print transfer timeline, cold/warm stage timing, and sample values.
9. Destroy events/streams and free SRAM/device/host memory.

## Workflow (ASCII Diagram)

```text
+-----------------------------+
| main()                      |
| allocate/init host buffers  |
+-------------+---------------+
              |
              v
+----------------------------------------+
| rtMalloc + rtMallocSram                |
| d_A/d_B/d_C + ping0/ping1/sram_B       |
+----------------+-----------------------+
                 |
                 v
+----------------------------------------+
| rppStreamCreate + rppEventCreate       |
| transfer_stream + compute_stream       |
+----------------+-----------------------+
                 |
                 v
+----------------------------------------+
| rppMemcpyHtoDAsync (A/B)               |
| host -> device DDR                     |
+----------------+-----------------------+
                 |
                 v
+----------------------------------------+
| rppMemcpyDtoSAsync (A->ping0, B->sram_B) |
| device DDR -> SRAM                     |
+----------------+-----------------------+
                 |
                 v
+----------------------------------------+
| cold run on compute_stream             |
| Add(ping0->ping1) -> Mul(ping1->ping0)|
| -> Add(ping0->ping1)                   |
+----------------+-----------------------+
                 |
                 v
+----------------------------------------+
| reload A to ping0, then warm run       |
| same Add -> Mul -> Add sequence        |
+----------------+-----------------------+
                 |
                 v
+----------------------------------------+
| rppMemcpyStoDAsync (ping1->d_C)        |
| SRAM -> device DDR                     |
+----------------+-----------------------+
                 |
                 v
+----------------------------------------+
| rppMemcpyDtoHAsync (d_C->h_C)          |
| device DDR -> host                     |
+----------------+-----------------------+
                 |
                 v
+----------------------------------------+
| print timing + cleanup                 |
+----------------------------------------+
```

## Build and Run

From `rpp_pingpong`:

```bash
mkdir -p build
cd build
cmake ..
make -j
./rpp_pingpong
```

The program prints transfer timing, cold/warm stage timing, launch configuration, async mode notes, and sample outputs.
