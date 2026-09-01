# WheelAthlete Python Research Edition

The Python Research Edition is a Windows desktop operator UI for WheelAthlete.
It is intentionally **not** the process that owns BLE or authoritative raw
data. A separate `tools.pc_acquisition` daemon owns both XIAO connections,
clock synchronization, strict parsing/sequence validation, the append-only
`.waj` journal, final QC, and recovery.

This process boundary is the main reliability feature: a slow chart, frozen
window, or GUI restart cannot become the raw BLE data path.

## Start

From the repository root on Windows:

```bat
run_python_pc_app.bat
```

## Windows portable build

From the repository root, run `build_windows.bat`. It creates
`release\WheelAthlete-1.7.0-portable.zip`, containing the GUI and its bundled
acquisition daemon. Extract the archive on another Windows PC and run
`WheelAthlete\WheelAthlete.exe`; the acquisition daemon is bundled and starts
automatically, so no Python installation or separate daemon setup is required.

For a normal Windows installation with Desktop and Start Menu shortcuts, run
`release\WheelAthleteSetup.exe`.

The launcher checks for PySide6 and Bleak, installs
`tools\pc_gui\requirements.txt` if they are missing, and starts the desktop
app. The UI starts a local acquisition daemon automatically when no daemon is
already listening on `127.0.0.1:8765`.

To inspect the UI without physical boards:

```bat
run_python_pc_app.bat --demo
```

Demo mode is clearly labeled `DEMO DATA`, generates only synthetic ~10 Hz
preview values, and never writes synthetic research evidence.

## Simple six-page workflow

### Dashboard

- scan and connect WheelAthlete Left/Right boards;
- board name, firmware, battery, RSSI and MTU;
- effective samples/s and synchronization metrics;
- loss and queue summary;
- board settings without a separate settings screen:
  - 50 / 100 / 200 Hz;
  - accelerometer ±2 / ±4 / ±8 / ±16 g;
  - gyroscope ±250 / ±500 / ±1000 / ±2000 deg/s;
- apply settings to Left, Right, or both;
- manual clock synchronization.

Board settings are locked while recording. After a range change the daemon
re-reads the firmware Info characteristic before reporting success, so live
raw-to-g / raw-to-deg/s conversion cannot silently keep stale scale factors.

### Live

- current Accel X/Y/Z and Gyro X/Y/Z for both wheels;
- one acceleration chart with L/R XYZ;
- one gyroscope chart with L/R XYZ;
- bounded 300-point preview history (~30 seconds at ~10 Hz).

Only throttled `sample_preview` telemetry enters the GUI. Raw 50/100/200 Hz
samples remain in the acquisition daemon and authoritative journal path.

### Record

- athlete, topic, trial, rate, tags and notes;
- configures every connected board before START;
- pre-record clock synchronization;
- common PC monotonic scheduled T0;
- requires firmware START acknowledgement;
- append-only raw journal;
- reliable STOP and post-stop synchronization;
- final QC display.

### Experiments

Simple reusable recording presets are stored crash-safely at:

`~/Documents/WheelAthlete/experiments.json`

A preset can fill athlete/topic/rate/tags/notes on the Record page.

### Sessions

- searchable finalized sessions;
- quality, duration and L/R sample counts;
- CSV export derived from `.waj`;
- open the session folder.

The `.waj` file remains the source of truth. CSV is an export artifact.

### Diagnostics

Side-by-side L/R data-path observability includes:

- RSSI, MTU, configured/effective rates and sensor ranges;
- host notifications/samples;
- sequence gaps, duplicates, out-of-order and malformed packets;
- host queue depth/high-water/overflow;
- firmware produced/notified counts;
- firmware queue drops/depth and transport failures;
- FIFO faults/sample loss when firmware exposes them;
- best/median synchronization RTT, drift and residual;
- UI IPC clients, preview sent/dropped and bounded socket buffer metrics;
- diagnostic JSON export;
- recovery of incomplete `.open` journals.

RSSI is displayed as RF context only; it is never treated as proof of data
integrity.

## Process and crash behavior

```text
XIAO Left ─┐
           ├─ Windows BLE / Bleak / WinRT
XIAO Right ┘
                 │
        Python Acquisition Daemon
        ├─ strict parser / sequence QC
        ├─ clock synchronization
        ├─ append-only .waj writer
        └─ final QC / recovery
                 │ localhost NDJSON
                 │ status/events/~10 Hz preview only
                 ▼
        PySide6 + QtCharts UI
```

- If the GUI starts the daemon and the GUI closes while **idle**, it terminates
  that child daemon cleanly.
- If a recording is active, closing the GUI requires confirmation and the
  daemon is deliberately left running so the UI close cannot destroy the raw
  acquisition session.
- An already-running daemon is reused rather than duplicated.
- UI socket traffic is event-driven with `QTcpSocket`; the GUI performs no
  blocking BLE reads or disk writes.

## Data locations

Default authoritative sessions:

`~/Documents/WheelAthlete/PC Sessions`

GUI log:

`~/Documents/WheelAthlete/Logs/python-pc-app.log`

Experiments:

`~/Documents/WheelAthlete/experiments.json`

## Verification

Automated tests live in `tools/pc_gui/tests`. They cover bounded preview state,
status mapping, experiment persistence, IPC protocol handling, and an offscreen
six-page GUI/demo/recording smoke path. The full acquisition suite is also run
against every Python UI checkpoint because the GUI intentionally reuses the
same production daemon rather than duplicating acquisition logic.

Physical BLE throughput, RF behavior, real L/R start skew, and 0.5/2/5 m
acceptance remain hardware measurements. Do not infer those results from demo
or automated tests.
