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
cd applications/wheelathlete_windows
run_wheelathlete_windows.bat
```

The source launcher checks the normal PySide6/Bleak dependencies and starts the
desktop app. The UI starts a local acquisition daemon automatically when no
daemon is already listening on `127.0.0.1:8765`.

To inspect the UI without physical boards:

```bat
cd applications/wheelathlete_windows
run_wheelathlete_windows.bat --demo
```

Demo mode is clearly labeled and does not write synthetic research evidence.

### MODEL runtime dependency

The `MODEL` page supports two local model types: the lightweight **BiWheel3D XY + Yaw current_best** recipe and compatible BiWheel3D **ONNX** learned models. PyTorch, a model server, and the friend `BiWheel3D` checkout are not required by the installed app. Source development installs NumPy plus ONNX Runtime:

```bat
python -m pip install -r tools\pc_gui\requirements-model.txt
```

The Windows installer seeds a user-editable model library at `~/Documents/WheelAthlete/Model/` with the current recipe, the validated M4 ONNX model, and its license. **Browse model…** can also run a compatible `.onnx` file from any location. `.pt` / `.pth` files should be exported to ONNX before use in the lean Windows app. The acquisition daemon remains independent of model code.

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
        ->
Saved per-board sensor scales
        ->
100 Hz dual-wheel SI preprocessing
        ->
5-sample windows / 20 Hz trajectory cadence
        ->
selected local model
  ├─ XY + Yaw recipe
  └─ BiWheel3D ONNX (90-feature protocol v10b)
        ->
2D trajectory (+ net yaw when the selected model exposes it)
```

Current capabilities:

- discovers supported models in `~/Documents/WheelAthlete/Model/`;
- exposes **Browse model…** for compatible `.onnx` and XY + Yaw recipe `.json` files;
- seeds the validated `wheelathlete_biwheel3d_m4.onnx` model automatically in Setup EXE installs;
- does not depend on the external friend `BiWheel3D` working tree at runtime;
- converts stored GUI units from g / deg/s to m/s^2 / rad/s using the **scales saved with the recording**;
- prepares synchronized Left/Right data at 100 Hz and groups five raw samples per 20 Hz trajectory step;
- reproduces the BiWheel3D v10b 90-feature extractor for M4 ONNX inference;
- keeps the current-best recipe with calibrated wheel-speed/chassis-yaw scaling and 27-frame pause-aware yaw delay;
- runs analysis in a background worker so acquisition UI remains responsive;
- displays estimated path, start/end points, path length, endpoint distance, point count, and net yaw when available;
- renders the 2D chart with equal physical X/Y scale: `1 m` on X equals `1 m` on Y.

The upstream snapshot currently references `biwheel3d.pause_segments` but does not contain that module. WheelAthlete therefore bundles the minimal documented >=1 s pause helper required by `yaw_ab.shift_heading_bursts()`. Provenance is recorded in `tools/pc_gui/biwheel3d_runtime/SOURCE.json`, and the upstream MIT license is included beside it. The large per-trial evaluation summary is intentionally not packaged because only the compact runtime recipe values are required.

MODEL output is derived preview data. It never joins the BLE/journal write path and must not be treated as the authoritative raw research record.

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
                 └─ optional offline BiWheel3D XY + Yaw worker
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

`~/Documents/WheelAthlete/Logs/wheelathlete-windows.log`

Experiment presets/settings used by the desktop workflow are stored under the
WheelAthlete documents/settings area as applicable.

## Windows portable build

From the repository root, run:

```bat
applications\wheelathlete_windows\packaging\windows\build_installer.bat
```

It creates the portable package and installer under ignored `applications/wheelathlete_windows/release/`. The
normal Windows distribution bundles `WheelAthleteDaemon.exe`; users do not need
to start a separate acquisition daemon manually.

The lightweight BiWheel3D XY + Yaw MODEL runtime is bundled with the packaged GUI; source runs require NumPy. It remains isolated from the acquisition daemon and raw-data write path.

## Verification

From the repository root:

```bat
cd applications/wheelathlete_windows
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
