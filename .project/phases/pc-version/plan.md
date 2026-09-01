# WheelAthlete — Windows PC Acquisition Plan

> Active branch: `codex/pc-version`
>
> Source task: `pc-version-promt.txt`
>
> Hard branch rule: **never merge/push/rebase/reset/force-update this work into
> `main` unless the user explicitly reverses that instruction in a future
> message.**

| Phase | Deliverable | Status |
|---|---|---|
| 0 | Repository, protocol, firmware, PC-tool, and Flutter audit | done |
| 1 | Feature-parity matrix, target architecture, baseline tests | done (`b970b69`) |
| 2 | XIAO timing, BLE link preferences/diagnostics, FIFO investigation | done (`8d0d0a9`) |
| 3 | Headless Python/Bleak dual-board engine | done (`857a164`) |
| 4 | Clock sync, scheduled start, START/STOP acknowledgements | done (`da6249a`) |
| 5 | Append-only journal, recovery, QC, exports | done (`118e1bc`) |
| 6 | Flutter Windows IPC/backend integration | done (`a8927ae`) |
| 7 | Preserve and regression-test Android behavior | done (`4b4aef9`) |
| 8 | Flutter Windows diagnostics/acquisition UI | done (`083d7c8`) |
| 9 | Simulated long-run and fault-injection tests | done (`f23d1c1`) |
| 10 | Physical two-XIAO acceptance | harness ready (`78b4fba`); physical execution BLOCKED until two boards are attached |
| 11 | Python Research Edition desktop UI | done (`9a96601`); automated/native smoke green |

## Current architecture

The authoritative acquisition path is shared by both PC user interfaces:

```text
XIAO Left ─┐
           ├─ Windows BLE / Bleak / WinRT
XIAO Right ┘
                 │
        Python Acquisition Daemon
        ├─ strict packet parser
        ├─ independent L/R bounded queues
        ├─ sequence validation
        ├─ PC monotonic clock mapping
        ├─ synchronized scheduled START/STOP
        ├─ append-only .waj raw journal
        ├─ recovery / CSV derivation
        └─ final QC
                 │ localhost versioned NDJSON
                 │ control/status/events/~10 Hz preview only
          ┌──────┴────────┐
          │               │
   Flutter Windows   Python PySide6 UI
          │               │
       operator         operator
          │               │
          └──── raw samples never enter either UI process
```

Android/mobile remains on its existing FlutterBluePlus path and is not replaced.

## Phase 10 physical acceptance

Preparation complete in:

- `tools/pc_acquisition/acceptance.py`
- `docs/testing/pc-version-phase-10-acceptance-plan.md`
- `docs/testing/pc-version-phase-10-plan.json`

The planned matrix includes 50/100/200 Hz, 0.5/2/5 m, 10-minute and 30-minute
records, and 20 repeated Start/Stop cycles. Planned raw recording time is 53.3
minutes before pre/post synchronization overhead.

Physical success must still be withheld until two real XIAO nRF52840 Sense
boards are connected and the matrix is measured.

## Phase 11 — Python Research Edition

Goal: provide a simpler research-first Windows application while retaining the
same isolated acquisition engine and all critical observability.

Implementation:

- PySide6 + QtCharts; no Flutter Windows toolchain is required for this UI;
- six pages only:
  1. Dashboard (connection + compact board settings),
  2. Live,
  3. Record,
  4. Experiments,
  5. Sessions,
  6. Diagnostics;
- separate GUI process from the DAQ daemon;
- Qt `QTcpSocket` event-driven IPC; no blocking BLE/disk work in the GUI;
- 1 Hz state polling and bounded ~10 Hz preview rendering;
- realtime L/R Accel XYZ + Gyro XYZ values;
- realtime L/R Acceleration and Gyroscope charts;
- rate/RSSI/MTU/battery/loss/queue/sync metrics;
- board settings: 50/100/200 Hz, ±2/4/8/16 g, ±250/500/1000/2000 deg/s;
- range changes re-read firmware Info before success so raw→physical scales
  cannot remain stale;
- synchronized recording metadata + final QC;
- reusable experiment presets;
- session search / CSV export;
- incomplete-journal recovery;
- full host/firmware/FIFO/sync/IPC diagnostics;
- `--demo` mode clearly labels synthetic data and never writes research evidence;
- `run_python_pc_app.bat` launcher;
- if GUI closes during an active record, the DAQ daemon is deliberately left
  running so UI lifecycle cannot destroy the raw recording.

Detailed usage: `tools/pc_gui/README.md`.

## Automated definition of done for Phase 11

- Python GUI unit/smoke tests green;
- full `tools/pc_acquisition/tests + tools/pc_gui/tests` green;
- Python compileall clean;
- real Windows `--demo` process launches and renders controls;
- real Windows normal process reaches `DAQ READY` using the production daemon;
- closing the idle GUI terminates a daemon it owns;
- no raw sample path is moved into Qt;
- branch confirmed as `codex/pc-version` before commit;
- `.project` documentation updated before commit.

## Hardware / packaging gates

### Two-XIAO gate

Still required for any claim about real RF throughput, negotiated connection
behavior, physical L/R start skew, real clock drift, FIFO/INT behavior, or
zero-loss physical recordings.

### Flutter Windows packaging gate

The older Flutter Windows UI still cannot produce a release executable on this
host because Visual Studio with the `Desktop development with C++` workload is
not installed. This does **not** block the Python Research Edition, which runs
with the installed Python/PySide6/Bleak environment.

## Final project definition of done

All software work that does not require physical boards is complete. Phase
11 is committed and the project remains open only for Phase 10's real two-XIAO
physical acceptance matrix. The working tree must remain clean after the final
tracker checkpoint.
