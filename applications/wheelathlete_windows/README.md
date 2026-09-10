# WheelAthlete Windows Research Application

The **WheelAthlete Windows Research Application** is the reliability-first Windows acquisition and research client. It uses a PySide6 operator interface and a separate Python acquisition daemon so BLE capture and authoritative raw-data recording remain isolated from UI rendering and optional analysis workloads.

Current package version: `1.8.2`

## Architecture

- `tools/pc_acquisition/` — authoritative BLE acquisition daemon, synchronization, sequence/loss accounting, journal storage, QC, and recovery.
- `tools/pc_gui/` — PySide6 operator interface, Results workflow, diagnostics, export, and optional offline MODEL integration.
- `packaging/windows/` — PyInstaller and Inno Setup packaging sources.
- `run_wheelathlete_windows.bat` — source launcher.
- `build/` and `release/` — generated artifacts; excluded from Git.

## Experimental PyTorch research review

The source MODEL page keeps the frozen BiWheel3D XY+yaw recipe first/default. If local PyTorch is available, a `torch_residual_v1` `.pt/.pth` checkpoint in `Documents/WheelAthlete/Model` can be selected explicitly as an experimental model. This does not change production `current_best` or the package requirements.

Use `Research trial…` to inspect a trusted processed `.npz` under this checkout's `BiWheel3D/data` tree. If the trial contains real C3D hub ground truth, the chart overlays it as a gray dashed path and labels the displayed errors as full-cache diagnostics. These are visual research diagnostics; model-selection claims still require the support-masked evaluator and frozen split protocol. IMU-only trials never receive fabricated GT.

When the optional local `BiWheel3D/registry/models.json` exists, the source app also discovers **Experimental PyTorch v1 + Slalom Course Constraint**. It keeps the exact residual-v1 weights and applies a fixed-course adapter only to sessions explicitly labeled `SL`/`slalom`; other maneuvers are exact no-ops. The UI reports whether heading/position closure was applied. This is research-only and does not replace the first/default classical model.

## Run from source

```bat
cd applications\wheelathlete_windows
run_wheelathlete_windows.bat
```

Demo UI without physical boards:

```bat
run_wheelathlete_windows.bat --demo
```

## Verify

```bat
python -m pytest tools\pc_acquisition\tests tools\pc_gui\tests -q
python -m compileall -q tools\pc_acquisition tools\pc_gui
```

## Build the Windows package

Prerequisites: Python 3.10+, PyInstaller, and Inno Setup 6.

```bat
packaging\windows\build_installer.bat
```

Generated packages are written to `release/`.

Public packages require a trusted RSA Authenticode code-signing certificate and RFC3161 timestamp URL. The build signs and verifies all packaged executable components, the daemon-stop helper, generated uninstaller, and installer, then writes `signing-report.json` plus `SHA256SUMS.txt`. An unsigned local build is suitable for development only and does not resolve download reputation warnings or Application Control error 4551.

Upgrade and uninstall run the installation-specific daemon shutdown helper first. It finishes an active journal before exit and blocks file removal if the daemon cannot stop. Recordings and custom models in the user's `Documents/WheelAthlete` tree are preserved.

Portable model bundles use a `wheelathlete-model.json` manifest and are documented in [`../../docs/model_analysis/MODEL_BUNDLES.md`](../../docs/model_analysis/MODEL_BUNDLES.md).

## Automatic updates

The installed PyInstaller application checks `releases/latest/download/latest.json` after startup and every six hours. Manual checking is available from the header. Installer downloads are accepted only from this repository's HTTPS GitHub Release path and must match both the exact manifest size and SHA-256.

An update can be downloaded while the UI is idle, but installation is blocked while Live preview, countdown, or recording is active. Once confirmed, WheelAthlete launches the verified Inno Setup installer with `/AUTOUPDATE=1`, exits cleanly, updates the existing stable AppId, and relaunches automatically. Source/demo mode can inspect releases but deliberately does not replace itself.

For the detailed operator/developer workflow, see [`tools/pc_gui/README.md`](tools/pc_gui/README.md). For the overall product architecture, see the repository-level [`README.md`](../../README.md) or [`README.th.md`](../../README.th.md).
