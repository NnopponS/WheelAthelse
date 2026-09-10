# WheelAthlete runtime architecture

Updated: 2026-09-08.

WheelAthlete maintains two operator applications and two firmware targets. The stable sensing baseline is two wheel-hub IMUs (`L`, `R`); source code now also supports an optional chair-center IMU (`C`) for future controlled experiments.

## Product and repository boundaries

```text
applications/wheelathlete_mobile/        Flutter Android/iOS; direct BLE ownership
applications/wheelathlete_windows/       Python/PySide6 GUI + acquisition daemon
hardware_firmware/m5stickc_plus2/        ESP32/M5StickC Plus2 sensor firmware
hardware_firmware/xiao_nrf52840_sense/   nRF52840/LSM6DS3 sensor firmware
docs/                                    BLE/model contracts and public fixtures
.project/                                project truth + ignored local evidence
scripts/                                 verification/hygiene tooling
BiWheel3D/                                separate local research repository
```

`BiWheel3D/` is not a root submodule and must not become a required runtime dependency. The Windows source app may discover its registry for explicit local research review. Installed/clean applications must continue to operate without the research checkout.

## Sensor roles

| Role | Identity | Physical meaning | Current model use |
|---|---|---|---|
| L | `0x4C` | left wheel-hub IMU | legacy/current L/R model input |
| R | `0x52` | right wheel-hub IMU | legacy/current L/R model input |
| C | `0x43` | optional chair-center/frame IMU | acquisition/storage only; ignored by current trajectory models |

Center mounting contract: **+Z points down toward the floor**. Center X/Y remain physical board axes until forward/lateral orientation is measured and documented. The code must not silently map C to R or reinterpret its axes.

## Acquisition ownership

```text
L/R[/C] -> BLE -> Flutter mobile -> mobile-native session storage

or

L/R[/C] -> BLE -> Windows acquisition daemon -> append-only .waj
                                            -> bounded localhost IPC -> Qt GUI
```

Only one operator client owns a sensor set at a time. Preview traffic may be bounded; authoritative raw capture may not silently drop data to preserve UI smoothness.

Windows `tools/pc_acquisition` owns BLE parsing, per-role sequence classification, synchronization, lifecycle, journal writes, QC and recovery. `tools/pc_gui` owns operator controls, preview, result browsing and optional offline analysis. The GUI must never become authoritative raw storage.

Flutter continues to own BLE directly; it does not depend on the Windows daemon or an HTTP inference service.

## Storage/version compatibility

The BLE 20-byte IMU sample payload remains unchanged. Role vocabulary is extended with C.

Windows:
- L/R-only journals retain journal v1 semantics.
- A recording containing C uses journal v2.
- v2 side codes are `L=0`, `R=1`, `C=2`.
- v1 fallback summaries must not fabricate `C:0` into historical session metadata.

Mobile:
- current metadata schema supports optional center fields and old-session parsing.
- `center_raw.csv` is emitted only for a recording that actually contains C.
- historical L/R training CSV/schema stays unchanged.

## Clock/timing architecture

Raw packet data retains device `uint32` microsecond timestamp, sequence, arrival timestamp and sequence classification. Saved pre-start clock models and START evidence establish the application's chosen device-to-client mapping. They do not independently prove physical synchronization.

Offline analysis uses recording-relative source time, explicit rollover/reset/gap handling and one whole-session result. BLE arrival time or independently zeroed device epochs must not be mislabeled as shared synchronized acquisition time.

For a future L/R/C model, C needs the same explicit clock provenance as both hubs. A third stream cannot be aligned by separately setting all starts to zero.

## Offline analysis/model boundary

### Windows default

The default remains the frozen classical XY+yaw recipe. It produces signed speed/yaw-rate and integrated pose under its documented frame assumptions.

### Experimental PyTorch residual v1

The Windows source app may explicitly load the residual BiGRU research model. Residual v1 predicts signed-speed/yaw-rate corrections over an L/R physics baseline. It remains research-only.

### Slalom constrained analysis

Course adapters operate **after** the L/R estimator and only for explicitly labeled Slalom conditions.

- v1: deterministic course heading/position closure under guards.
- v2: rejected for accuracy claims because exploratory finite-difference optimization was numerically unstable and did not reproduce in app runtime.
- v3: residual-v1 weights frozen; train-derived small linear yaw/speed calibration + sign-aware turn detection + guarded closure. C3D is never an inference input.

Near-zero final pose from a closure constraint is not evidence that unconstrained inertial odometry returned to zero. UI/export metadata must expose raw and constrained states/corrections.

### Mobile

Mobile keeps the existing M4 XY-only ONNX model. Chair yaw/rate, signed forward speed and signed longitudinal acceleration remain unavailable unless a future accepted model provides them. XY tangent is not chair heading.

### Center isolation

Current model preprocessing explicitly selects L/R. Tests require exact legacy input equality when arbitrary C samples are added. C must never enter the existing `(T,5,12)` input by enum iteration, implicit concatenation or fallback.

A future center-aware model is a new estimator contract, likely with a different input dimension/feature identity. It requires new L/R/C training data, grouped validation and final acceptance; it is not a schema-only upgrade.

## UI/result architecture

Windows and mobile hold one full-session analysis result. Cursor/window selection references original samples and never restarts the estimator. Rendering may decimate visually, but statistics/export use full source arrays.

Missing quantities are null/unavailable, not zero. Derivative support/gaps must remain explicit. Exports are create-only and must not mutate original recordings.

Center capture is visible independently of model analysis: live/saved preview and raw export may show C even though the trajectory model ignores it.

## Firmware identity behavior

XIAO center: yellow RGB identity (`red + green`, blue off), with visible identity blink and recording heartbeat. Error/retry states have priority.

M5 center: yellow identity bar plus large yellow `C`; the glyph blinks/heartbeats without clearing large LCD rectangles, preserving the anti-flicker display rule.

Successful compile is source/build evidence only. Physical orientation, sensor ranges, RF behavior, timing and data loss require hardware acceptance.

## Updates, packaging and publication

Stable product/version identity remains unchanged. Feature work may not be called a release merely because firmware or apps compile.

Root feature branch publication is independent of the dirty working tree. The separate research repository, raw data, generated research models, local evidence and firmware binaries/ZIPs are not to be published by default.

Use STATUS for measured current state, HANDOFF for continuation, decisions for durable policy and phase files for conclusions.
