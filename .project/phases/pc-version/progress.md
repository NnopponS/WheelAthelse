# PC Version — Progress

Updated: 2026-09-01 (Asia/Bangkok)
Active branch: `codex/pc-version`

## Non-negotiable branch constraint

The user explicitly instructed that this work must **never be put into
`main`**. All implementation, tests, tracker updates and local commits remain on
`codex/pc-version`. No merge, rebase, reset, force-update, push, or other
mutation of `main` is part of this task.

## Completed checkpoints

- Phase 1 `b970b69`: parity / architecture baseline.
- Phase 2 `8d0d0a9`: XIAO BLE/timing hardening, coherent 12-byte IMU burst,
  explicit connection preference, diagnostics; FIFO activation remains
  hardware-gated.
- Phase 3 `857a164`: strict headless dual-board ingestion engine with independent
  bounded per-wheel queues, sequence validation and fail-closed overflow.
- Phase 4 `da6249a`: monotonic PC clock mapping, low-RTT sync, common scheduled
  T0, START_FIRED/STOP_FIRED, reliable STOP and disconnect failsafe.
- Phase 5 `118e1bc`: append-only `.waj`, CRC, crash recovery, atomic finalize,
  derived CSV and fail-closed QC.
- Phase 6 `a8927ae`: versioned localhost IPC; daemon owns raw samples while UI
  receives only control/state/health/throttled preview.
- Phase 7 `4b4aef9`: Android regression checkpoint; mobile remains on
  FlutterBluePlus and does not depend on the desktop daemon.
- Phase 8 `083d7c8`: Flutter Windows operator UI + diagnostics.
- Phase 9 `f23d1c1`: simulated long-run/fault hardening.

## Phase 9 reliability evidence retained

- 30-minute-equivalent dual-wheel simulations:
  - 50 Hz: 90,000 samples/wheel;
  - 100 Hz: 180,000 samples/wheel;
  - 200 Hz: 360,000 samples/wheel;
- no-yield 400-notification burst/wheel;
- 720,000-sample dual-200-Hz journal stress;
- slow-disk queue saturation rejects new input rather than overwriting unread
  samples;
- injected disk-write failure creates a fatal writer fault;
- final QC checks journal-written == host-received;
- slow/frozen UI can drop only disposable preview traffic;
- raw acquisition remains isolated from UI backpressure.

Detailed evidence: `docs/testing/pc-version-phase-09.tdd.md`.

## Phase 10 — physical acceptance preparation complete

Physical execution is still blocked because two real XIAO nRF52840 Sense boards
are not connected, but all preparation that can be done without hardware is in
the working tree:

- `tools/pc_acquisition/acceptance.py` uses the real production
  `AcquisitionService` and authoritative `.waj` files rather than a second data
  path;
- physical matrix encoded in
  `docs/testing/pc-version-phase-10-plan.json`;
- operator instructions in
  `docs/testing/pc-version-phase-10-acceptance-plan.md`;
- planned raw recording time = **53.3 minutes**;
- matrix includes 50/100/200 Hz, 0.5/2/5 m, 10 min, 30 min and 20 Start/Stop
  cycles;
- acceptance journal evaluation is bounded-memory;
- direct `.waj` inspection can reject sequence loss even if a stored final
  summary incorrectly claimed GOOD;
- RSSI scan path uses Bleak advertisement data where available;
- host sequence epoch is reset at every new scheduled START to match XIAO
  firmware resetting sequence to zero at each recording.

No physical success is claimed for this phase yet.

## Phase 11 — Python Research Edition implemented

The user requested a second PC application written in Python, prioritizing
stability, simplicity and complete realtime visibility. The existing Flutter
Windows/mobile implementations remain intact.

### Architecture

The Python UI **does not own BLE**. It is a separate PySide6 process using the
same acquisition daemon already stress-tested in Phases 3–9:

`two XIAOs → Bleak/WinRT daemon → parser/sync/.waj/QC → localhost IPC → PySide6 UI`

Only status, lifecycle events and ~10 Hz `sample_preview` telemetry enter Qt.
Raw 50/100/200 Hz data never crosses into the GUI process.

### UI stack

- PySide6;
- QtCharts for realtime graphs;
- Qt `QTcpSocket` for non-blocking IPC;
- no PyQtGraph dependency required;
- no Visual Studio Flutter/C++ toolchain required for this Python UI.

### Six-page simplified workflow

1. **Dashboard**
   - scan/connect L/R;
   - device/FW, battery, RSSI, MTU;
   - effective samples/s, loss, queue, RTT, drift;
   - Sync clocks;
   - compact Board Settings on the same page:
     - 50/100/200 Hz,
     - ±2/4/8/16 g,
     - ±250/500/1000/2000 deg/s,
     - Apply L / R / both.
2. **Live**
   - current Accel XYZ + Gyro XYZ for both wheels;
   - acceleration chart showing L/R XYZ;
   - gyroscope chart showing L/R XYZ;
   - bounded 300-point (~30 s) preview history;
   - 10 Hz GUI refresh to keep chart work out of the acquisition path.
3. **Record**
   - athlete/topic/trial/rate/tags/notes;
   - configures all connected boards before START;
   - daemon performs pre-sync, common PC T0, scheduled START, raw journal,
     reliable STOP, post-sync and final QC;
   - final GOOD/WARNING/DEGRADED/INVALID result shown in UI.
4. **Experiments**
   - reusable presets for athlete/topic/rate/tags/notes;
   - crash-safe atomic JSON at
     `~/Documents/WheelAthlete/experiments.json`;
   - preset applies directly to Record.
5. **Sessions**
   - search finalized sessions;
   - quality/duration/rate/L-R sample counts;
   - CSV export derived from `.waj`;
   - open session folder.
6. **Diagnostics**
   - RSSI, MTU, ranges, configured/effective rates;
   - host packets/samples, gaps, duplicates, out-of-order, malformed;
   - host queue depth/high-water/overflow;
   - firmware produced/notified/queue drops/transport/FIFO;
   - sync RTT/drift/residual;
   - IPC client/preview sent/drop/buffer metrics;
   - diagnostic JSON export;
   - incomplete `.open` recovery.

### Safety / lifecycle behavior

- The UI automatically reuses an existing daemon or starts one when needed.
- A GUI-owned daemon is terminated when the GUI exits while idle.
- If recording is active, closing the GUI requires confirmation and **does not
  terminate the daemon**, so GUI lifecycle cannot destroy an active raw
  recording.
- `sample_preview` is display-only and disposable; `.waj` remains authoritative.
- `--demo` displays a clear `DEMO DATA` badge and never writes synthetic
  research evidence.
- GUI crashes are logged at
  `~/Documents/WheelAthlete/Logs/python-pc-app.log`.

### Board range correctness hardening

While adding settings parity, a backend correctness issue was found: SET_RANGE
previously updated cached range codes but could leave cached accel/gyro scale
factors stale until reconnect. `AcquisitionService._cmd_configure` now:

1. sends SET_RANGE;
2. re-reads the firmware Info characteristic;
3. verifies the wheel identity did not change;
4. replaces cached range codes **and scales** with firmware-authoritative
   values before returning success.

This prevents the Python Live page from silently converting raw values with a
stale g / deg/s scale. Regression coverage is in
`tools/pc_acquisition/tests/test_range_scale_refresh.py`.

### Files

- `tools/pc_gui/__main__.py`
- `tools/pc_gui/controller.py`
- `tools/pc_gui/ipc_client.py`
- `tools/pc_gui/process_manager.py`
- `tools/pc_gui/state.py`
- `tools/pc_gui/widgets.py`
- `tools/pc_gui/main_window.py`
- `tools/pc_gui/experiments.py`
- `tools/pc_gui/requirements.txt`
- `tools/pc_gui/README.md`
- `run_python_pc_app.bat`

### Phase 11 verification evidence

Targeted range + GUI test run:

- `python -m pytest tools/pc_acquisition/tests/test_range_scale_refresh.py tools/pc_gui/tests -q --durations=10`
  - **11 passed in 0.84 s**;
  - GUI smoke portion ~**0.21 s**.

Final combined Python gate on the current source tree:

- `python -m pytest tools/pc_acquisition/tests tools/pc_gui/tests -q`
  - **50 passed in 20.12 s**.
- `python -m compileall -q tools/pc_acquisition tools/pc_gui`
  - clean.

Native Windows smoke:

- `python -m tools.pc_gui --demo`
  - real window launched successfully;
  - Dashboard board-settings controls present with no observed overflow;
  - synthetic realtime state active;
- `python -m tools.pc_gui`
  - real window launched successfully;
  - acquisition daemon auto-started;
  - header reached **DAQ READY**;
  - closing GUI while idle terminated its child daemon;
  - subsequent `127.0.0.1:8765` connect test returned Windows socket error
    `10035`, confirming no listener remained.

Usage documentation: `tools/pc_gui/README.md`.

## Remaining physical blockers

No claims are made yet for:

- real modified-firmware flash/boot behavior;
- negotiated link parameters on the actual Windows Bluetooth controller;
- real RF throughput/loss at 0.5/2/5 m;
- real 50/100/200 Hz two-wheel equality;
- physical `produced == notified == received == journal-written`;
- real Left/Right start skew;
- real synchronization RTT/drift;
- physical 2/10/30-minute records;
- physical 20-cycle Start/Stop;
- hardware FIFO/INT1 behavior.

These remain Phase 10 and require two physical XIAO boards.

## Current completion state

All new Python Research Edition software requested by the user is implemented
and passes automated/native no-hardware verification. Remaining housekeeping:
commit the Phase 10 preparation + Phase 11 Python application on
`codex/pc-version`, confirm clean working tree, and leave physical Phase 10
explicitly BLOCKED rather than fabricating a hardware result.
