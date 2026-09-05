# WheelAthlete PC Version — Phase 10 Physical Two-XIAO Acceptance

Date prepared: 2026-09-01 (Asia/Bangkok)
Branch: `codex/pc-version`
Execution status: **READY / BLOCKED UNTIL TWO PHYSICAL XIAO BOARDS ARE AVAILABLE**

## Purpose

This phase is the only place where the project may make real claims about BLE
packet loss, negotiated MTU, RF behavior, physical effective rate, Left/Right
start skew, or sustained two-board reliability.

Automated Phase 9 evidence is deliberately insufficient for these claims.
Phase 10 must run the production acquisition path:

`XIAO L + XIAO R -> Windows BLE/Bleak -> AcquisitionService -> .waj -> acceptance evaluator`

The harness is `tools/pc_acquisition/acceptance.py`. It does not contain a
second data collector and does not use Flutter graphs as evidence.

## Branch safety

All acceptance tooling and future physical evidence stay on
`codex/pc-version`. The user explicitly prohibited putting this PC-version work
into `main`.

## Prerequisites

1. Two Seeed Studio XIAO nRF52840 Sense boards, one flashed as LEFT and one as
   RIGHT from the current `codex/pc-version` source.
2. Firmware reports hardware model `2` and expected firmware `1.8.0`.
3. Both boards are powered and advertising as WheelAthlete devices.
4. Windows Bluetooth is enabled on the acquisition PC.
5. No phone/mobile WheelAthlete instance is connected to either board.
6. PC sleep/hibernation is disabled for the duration of long tests and the PC
   is on stable power.
7. Keep the same Windows Bluetooth adapter/controller for the whole matrix.
8. Python dependencies from `tools/pc_acquisition/requirements.txt` are
   installed.

The Python PySide6 GUI is not required to execute the headless physical`r`nacceptance harness. The acceptance path intentionally uses the production`r`nacquisition service directly so UI rendering cannot influence raw-data evidence.

## Firmware build / flash

Build evidence already passes for both environments:

```text
cd Xiao_firmware
pio run -e left
pio run -e right
```

When boards are physically available, flash the corresponding environment using
the established PlatformIO upload method for each board. Flash/boot success is
not considered verified until that is performed on the actual boards.

## Inspect the prescribed matrix

From repository root:

```text
python -m tools.pc_acquisition.acceptance plan
```

Machine-readable plan:

`docs/testing/pc-version-phase-10-plan.json`

The prescribed matrix is:

| Case | Rate | Record duration | Distance | Purpose |
|---|---:|---:|---:|---|
| `50hz-120s-0p5m` | 50 Hz | 2 min | 0.5 m | low-rate validation |
| `100hz-120s-0p5m` | 100 Hz | 2 min | 0.5 m | short baseline |
| `200hz-120s-0p5m` | 200 Hz | 2 min | 0.5 m | high-rate validation |
| `100hz-120s-2m` | 100 Hz | 2 min | 2 m | medium-distance RF |
| `100hz-120s-5m` | 100 Hz | 2 min | 5 m | maximum planned distance |
| `100hz-600s-0p5m` | 100 Hz | 10 min | 0.5 m | sustained validation |
| `100hz-startstop-20x-0p5m` | 100 Hz | 10 s × 20 | 0.5 m | lifecycle repetition |
| `100hz-1800s-0p5m` | 100 Hz | 30 min | 0.5 m | long-run acceptance |

Planned raw recording time is 3,200 seconds = **53.3 minutes**, excluding
pre/post synchronization and operator placement time.

## Recommended execution

Use the matrix runner:

```text
python -m tools.pc_acquisition.acceptance run-matrix
```

The harness pauses before each case and asks the operator to place the sensors
at the declared distance. Do not use `--yes` for formal evidence unless the
physical placement has already been independently controlled.

The default behavior stops after the first failed case. This is intentional:
do not waste a 30-minute run when a short preflight case already shows a data
integrity problem.

A single case can be rerun with:

```text
python -m tools.pc_acquisition.acceptance run-case 100hz-120s-0p5m
```

By default the production journals are written under:

`%USERPROFILE%\Documents\WheelAthlete\PC Sessions`

and acceptance case/report JSON is written under its `acceptance` subfolder.

## Pre-record physical checks performed by the harness

For every independent case the harness:

1. performs five BLE scan rounds before connecting;
2. records AdvertisementData RSSI samples for the eventual Left/Right devices;
3. connects candidates and verifies one XIAO hardware-model 2 board per wheel;
4. records firmware, device IDs and negotiated MTU;
5. rejects a case before recording if either MTU is below 185;
6. verifies expected firmware version;
7. configures both boards to the requested 50/100/200 Hz;
8. stores case ID, cycle, declared distance and RSSI evidence inside session
   metadata as well as the external acceptance report.

RSSI is recorded as a diagnostic distribution (values/min/max/mean). RSSI alone
is never treated as connection quality and there is no RSSI pass threshold.

## Recording path

Each cycle uses the same production `start_record` / `end_record` lifecycle as
the PC application:

1. pre-record clock synchronization;
2. drain any previous host notification epoch;
3. reset the host sequence tracker because firmware resets sequence to zero on
   each START;
4. schedule the same future PC T0 onto both device clocks;
5. require START_FIRED;
6. stream only during the recording interval;
7. STOP with bounded retry/failsafe behavior;
8. require final firmware health/STOP_FIRED;
9. drain host and authoritative journal queues;
10. post-stop clock synchronization;
11. finalize `.waj` and QC;
12. independently re-read the finalized `.waj` with the Phase 10 evaluator.

## Hard pass criteria for every cycle

A cycle passes only when all hard checks pass. In particular:

- finalized journal CRC/frame validation is clean;
- final QC is `GOOD`;
- no ERROR journal record exists;
- both boards are XIAO model 2 running expected firmware;
- negotiated MTU is at least 185 for both boards;
- both wheels have samples and first sequence is zero;
- sequence gaps = 0;
- duplicate samples = 0;
- out-of-order samples = 0;
- malformed/unknown sequence evidence = 0;
- START_FIRED is acknowledged by both wheels;
- Left/Right start skew is less than one sample period:
  - <20 ms at 50 Hz;
  - <10 ms at 100 Hz;
  - <5 ms at 200 Hz;
- desired start skew is <5 ms and is reported separately from the hard gate;
- STOP is acknowledged by each wheel with no error;
- final firmware queue depth = 0;
- firmware queue drops = 0;
- transport failures = 0;
- FIFO faults = 0;
- FIFO dropped samples = 0;
- for each side:
  `produced == notified == host received`;
- authoritative journal written sample count equals decoded Left + Right count;
- journal writer overflow = 0 and no journal fatal fault;
- pre-record and post-stop sync evidence exists for both wheels;
- effective sample rate is within ±5% of configured rate;
- measured duration is within max(2 s, 5%) of the prescribed case duration.

The evaluator intentionally performs stricter acceptance than a normal UI
quality badge. For example, a recovered transport retry may be useful in normal
operation but formal physical acceptance requires `transport_failures == 0`.

## Synchronization evidence recorded

The report preserves, per board:

- best RTT;
- median RTT;
- clock-fit residual where available;
- observation count;
- drift ppm;
- post-stop clock model;
- common-T0 mapped START evidence;
- measured Left/Right START_FIRED skew.

Do not claim 1–2 ms synchronization unless the measured physical report
actually supports it.

## Why the evaluator reads `.waj` again

The finalized service QC is not the sole acceptance authority. The harness
stream-reads the CRC-validated `.waj` and independently counts samples,
sequence classifications, health records, lifecycle records and sync records.
This catches evidence inconsistencies even if a final summary were accidentally
optimistic.

`JournalReader.iter_records()` performs bounded-memory iteration so a 30-minute
recording does not need to become hundreds of thousands of Python objects held
at once.

## Re-evaluate an existing session

A finalized journal can be checked without reconnecting hardware:

```text
python -m tools.pc_acquisition.acceptance summarize path\to\session.waj \
  --expected-rate 100 --expected-duration 120
```

Exit code is 0 only when the hard acceptance checks pass.

## Repeated Start/Stop requirement

`100hz-startstop-20x-0p5m` performs 20 independent 10-second recordings while
keeping the pair connected. Every cycle must pass independently.

This test specifically guards the firmware behavior that resets `seq` to zero
on every START. The PC host now drains the previous notification epoch and
resets its sequence classifier at the matching recording boundary; automated
regression tests cover this before physical execution.

## Overall PASS rule

The overall physical report is PASS only when every prescribed case is present
and every cycle in every case passes. Missing cases produce `BLOCKED`; failed
completed cases produce FAIL when the complete matrix is otherwise present.

`physical_claims_allowed` remains false until the complete matrix passes.

## Current status

The harness, plan generation and synthetic evidence evaluator can be automated
without boards. The actual Phase 10 matrix is still **BLOCKED** because two
physical XIAO nRF52840 Sense boards are not connected/available in this task.
No physical zero-loss, RF-distance, real-MTU or synchronization claim should be
made yet.
