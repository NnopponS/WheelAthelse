# WheelAthlete runtime architecture

Updated: 2026-09-08. The product has two maintained operator applications and two firmware targets. Neither Flutter Windows/Web nor the legacy Tkinter interface is maintained.

## Product and repository boundaries

```text
applications/wheelathlete_mobile/   Flutter, Android/iOS, direct BLE ownership
applications/wheelathlete_windows/ Python/PySide6 GUI plus acquisition daemon
hardware_firmware/m5stickc_plus2/  ESP32/M5StickC Plus2 sensor firmware
hardware_firmware/xiao_nrf52840_sense/  nRF52840/LSM6DS3 sensor firmware
docs/                             Protocol, capture guide, API contract, fixtures
.project/                         Current state and ignored local evidence
scripts/                          Portable verification and hygiene checks
```

`BiWheel3D/` is a separate local research repository, not an application dependency or a root submodule. The Windows app vendors a minimal attributed runtime. Do not overwrite its source/metadata to match an unaccepted research candidate.

## Acquisition ownership

```text
Left/right wheel IMUs -> BLE -> Flutter mobile -> mobile-native session storage
OR
Left/right wheel IMUs -> BLE -> acquisition daemon -> append-only .waj journal
                                                  -> bounded localhost IPC -> Qt GUI
```

Only one operator application may own a given sensor pair at a time. Both clients use the contract in `docs/ble-protocol.md`. Configuration, lifecycle acknowledgements, sequence/loss accounting, clock/drift evidence and replay/recovery remain explicit. RSSI and a smooth chart are not data-integrity measurements.

On Windows, `tools/pc_acquisition` is authoritative for parsing, timing, journal writes, QC and recovery. `tools/pc_gui` handles control, preview, results and optional analysis. Disposable preview traffic may be bounded; raw data may not be silently dropped to keep a chart responsive. Incomplete journals must remain recoverable independently of GUI lifecycle.

Mobile keeps direct BLE acquisition and its existing versioned session-storage/export format. It does not need the Windows daemon, an HTTP inference server or a replacement .waj storage layer.

## Offline analysis

Windows loads finalized journals using immutable capture conversion scales and saved pre-START clock evidence. `analysis_timing.py` aligns/resamples SI input to 100 Hz and groups five samples for each 20 Hz model step. `model_inference.py` applies the frozen bundled classical XY+yaw recipe in a worker and preserves signed speed, unwrapped yaw/rate and declared frames. `analysis_contract.py` adds supported derivatives, finite/null validation and full-resolution window statistics.

Mobile prepares saved-time input and features in compute isolates and runs the existing M4 XY-only ONNX asset locally. Its matching contract does not make its predictions equivalent to the Windows estimator. Chair yaw/rate, signed forward speed and signed longitudinal acceleration remain unavailable. XY-derived magnitude and magnitude-change quantities are labeled separately.

Both UIs hold one full-session result. Time/window controls select source samples; they never rerun inference, reset pose or use chart decimation for statistics. CSV/JSON export creates a unique new directory with a content hash and final COMPLETE marker. Originals and previous exports are not overwritten. Mobile full-timeline export serialization/hashing runs outside the UI isolate.

Models remain offline methods, not validated causal streaming estimators. Physical synchronization and motion accuracy require independent evidence beyond a saved clock map or passing unit tests.

## Updates and packaging

Existing update discovery consumes the stable GitHub release manifest, validates artifact size/hash and defers installation during acquisition. Android installation remains OS-approved and signing-key constrained. iOS delegates installation to App Store/TestFlight. Installed Windows builds use the Inno Setup identity; source/demo/portable runs do not replace themselves.

Windows packaging source lives under `applications/wheelathlete_windows/packaging/windows/`; generated output stays in ignored build/release directories. The new `verify.yml` workflow only tests source and has read-only repository permissions; it does not sign, package, flash or publish. Existing release automation remains separate.

The stable root VERSION, mobile version/build, firmware and BLE protocol metadata are unchanged by this feature branch. New source code on GitHub is not automatically an installed application update.

## Evidence and current state

Use STATUS.md for phase state, HANDOFF.md for continuation, and decisions.md for constraints. Public contract/fixtures live under `docs/model_analysis/`. Raw/derived participant data, historical snapshots and local commands belong in ignored `.project/local/`. Keep only sanitized measured summaries under `.project/reports/`.
