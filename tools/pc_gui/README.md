# WheelAthlete Python Research Edition

The Python Research Edition is the Windows desktop operator UI for WheelAthlete.
It is intentionally **not** the process that owns BLE or authoritative raw
data. A separate `tools.pc_acquisition` daemon owns both wheel connections,
clock synchronization, strict parsing/sequence validation, the append-only
`.waj` journal, final QC, and recovery.

This process boundary is the main reliability feature: a slow chart, model
inference, frozen window, or GUI restart cannot become the raw BLE data path.

## Start

From the repository root on Windows:

```bat
run_python_pc_app.bat
```

The source launcher checks the normal PySide6/Bleak dependencies and starts the
desktop app. The UI starts a local acquisition daemon automatically when no
daemon is already listening on `127.0.0.1:8765`.

To inspect the UI without physical boards:

```bat
run_python_pc_app.bat --demo
```

Demo mode is clearly labeled and does not write synthetic research evidence.

### Optional MODEL dependencies

The experimental `MODEL` page uses optional ML dependencies and does **not**
change the normal launcher or acquisition runtime. Install them only on a
research machine that will run BiWheel3D/PyTorch inference:

```bat
python -m pip install -r tools\pc_gui\requirements-model.txt
```

## Current five-section workflow

### Dashboard

- scan and connect WheelAthlete Left/Right boards;
- board name, firmware, battery, RSSI and MTU;
- effective samples/s and synchronization metrics;
- loss and queue summary;
- board settings:
  - 50 / 100 / 200 Hz;
  - accelerometer ±2 / ±4 / ±8 / ±16 g;
  - gyroscope ±250 / ±500 / ±1000 / ±2000 deg/s;
- apply settings to Left, Right, or both;
- manual clock synchronization.

Board settings are locked while recording. After a range change the daemon
re-reads the firmware Info characteristic before reporting success, so live
raw-to-g / raw-to-deg/s conversion cannot silently keep stale scale factors.

### Acquisition

The Acquisition page combines live telemetry and recording into one operator
workflow:

- current Accel X/Y/Z and Gyro X/Y/Z for both wheels;
- acceleration and gyroscope charts using bounded preview traffic;
- athlete, topic, trial, rate, tags and notes;
- configures every connected board before START;
- pre-record clock synchronization;
- common PC monotonic scheduled T0;
- firmware START acknowledgement;
- append-only raw journal recording;
- reliable STOP and post-stop synchronization;
- final QC result.

Only throttled preview telemetry enters the GUI. Raw 50/100/200 Hz samples stay
inside the acquisition daemon and authoritative journal path.

### Results

Results is the user-facing session browser and export workspace.

- **Group by Topic** and **All Trials Table** views;
- quality, duration and L/R sample counts;
- telemetry Preview with signal-loss information;
- checkbox-based batch CSV export and delete;
- one selected recording can be sent directly to the MODEL page;
- direct inline metadata correction for Topic, Trial and Athlete;
- confirmation before any metadata/file rename;
- editable group/topic names with one confirmation for the whole group.

Double-click the editable text rather than using a separate Edit button.
Checkboxes are reserved for batch actions, and row selection highlighting is
disabled so editing never covers the Preview control.

Finalized sessions keep their immutable internal UUID but are stored using
human-readable paths such as:

```text
~/Documents/WheelAthlete/PC Sessions/
└── 10x5/
    ├── 10x5_Trial16_Nipoon.waj
    └── 10x5_Trial16_Nipoon.summary.json
```

Renaming `10x5 / Trial 16 / Nipoon` updates the user-facing file/folder name and
summary metadata while leaving the UUID and append-only raw journal identity
unchanged. Duplicate friendly names are collision-safe and never overwrite an
existing session.

The `.waj` file remains the source of truth. CSV and MODEL trajectories are
derived artifacts.

### MODEL (experimental)

The MODEL page performs offline analysis only:

```text
Finalized Results session
        ↓
Select checkpoint
        ↓
Dual-wheel preprocessing
        ↓
PyTorch / BiWheel3D inference
        ↓
2D XY trajectory
```

Current capabilities:

- choose a discovered compatible checkpoint;
- use **Browse model…** to select a `.pt` / `.pth` checkpoint from Windows File Explorer;
- validate checkpoint compatibility before inference rather than silently forcing a mismatched model;
- prepare synchronized Left/Right data at the current BiWheel3D 100 Hz input contract;
- convert stored GUI units from g / deg/s to m/s² / rad/s;
- group five raw samples per model step for the current 20 Hz inference contract;
- run inference in a background worker so the GUI remains responsive;
- display predicted path, start/end points, path length, endpoint distance and model-point count;
- render the 2D chart with true equal physical X/Y scale: `1 m` on X equals `1 m` on Y.

The existing TCN + BiLSTM model is buffered/offline rather than a zero-latency
causal streaming estimator. MODEL analysis never joins the BLE or journal write
path and must not be treated as authoritative research evidence.

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
                 │
                 └─ optional offline PyTorch MODEL worker
```

- If the GUI starts the daemon and the GUI closes while **idle**, it terminates
  that child daemon cleanly.
- If a recording is active, closing the GUI requires confirmation and the
  daemon is deliberately left running so the UI close cannot destroy the raw
  acquisition session.
- An already-running daemon is reused rather than duplicated.
- UI socket traffic is event-driven with `QTcpSocket`; the GUI performs no
  blocking BLE reads or authoritative journal writes.
- MODEL inference reads finalized sessions only and is isolated from the raw
  acquisition path.

## Data locations

Default authoritative sessions:

`~/Documents/WheelAthlete/PC Sessions`

GUI log:

`~/Documents/WheelAthlete/Logs/python-pc-app.log`

Experiment presets/settings used by the desktop workflow are stored under the
WheelAthlete documents/settings area as applicable.

## Windows portable build

From the repository root, run:

```bat
packaging\windows\build_installer.bat
```

It creates the portable package and installer under ignored `release/`. The
normal Windows distribution bundles `WheelAthleteDaemon.exe`; users do not need
to start a separate acquisition daemon manually.

The experimental PyTorch MODEL runtime is intentionally optional and should be
validated separately when preparing an ML-enabled research workstation/package.

## Verification

From the repository root:

```bat
python -m pytest tools\pc_acquisition\tests tools\pc_gui\tests -q
python -m compileall -q tools\pc_acquisition tools\pc_gui
```

Automated coverage includes bounded preview state, Results grouping/export,
preview persistence, human-readable session storage, inline rename confirmation,
group rename, session path resolution, MODEL preprocessing/checkpoint browsing,
Results → MODEL navigation, and equal-scale trajectory rendering.

Physical BLE throughput, RF behavior, real L/R start skew, real-world model
accuracy, and hardware behavior at distance remain physical/validation
measurements. Do not infer those results from demo or automated tests.
