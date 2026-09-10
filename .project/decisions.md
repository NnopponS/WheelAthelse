# WheelAthlete current engineering decisions

Updated: 2026-09-08.

Only active durable decisions belong here. Historical experiment outcomes belong in phase/history files.

## D1 - Maintained applications

WheelAthlete maintains:
- Flutter mobile for Android/iOS.
- Python/PySide6 Windows Research Edition.

Flutter Windows/Web and the retired Tkinter GUI are not maintained product paths.

## D2 - One BLE protocol, explicit role semantics

Both clients use `docs/ble-protocol.md`. Role bytes are `L=0x4C`, `R=0x52`, optional chair-center `C=0x43`. Packet/command semantic changes require coordinated clients/firmware documentation and compatibility tests.

## D3 - L/R remains the model baseline; C is optional instrumentation

L/R wheel hubs remain the baseline sensing configuration and current model input. The user has authorized source support for optional center sensor C. This authorization does not establish that C improves trajectory accuracy.

C is a chair-frame IMU with declared **+Z down toward the floor**. X/Y remain board axes until physically mapped. Do not call C a wheel or infer its forward/lateral axes from convenience.

## D4 - Supported acquisition rates

Supported board acquisition rates are 50, 100 and 200 Hz. Configuration must be applied to the actual connected boards; metadata alone is not configuration evidence.

## D5 - Mobile owns BLE directly

Mobile uses its native BLE path and remains independent of the Windows acquisition daemon/server.

## D6 - Windows raw data ownership stays outside the GUI

`tools.pc_acquisition` owns BLE, clocks, sequence/loss accounting, raw journal writes, QC and recovery. `tools.pc_gui` receives state/preview/control over localhost IPC. Preview may drop; raw capture must fail visibly rather than silently overwrite unread data.

## D7 - Windows `.waj` is authoritative

Windows raw recording truth is append-only `.waj`; CSV is derived. L/R-only recordings keep journal v1. Recordings containing C use journal v2 with explicit C side code. Readers must preserve historical v1 semantics.

## D8 - Mobile storage remains mobile-native and backward-compatible

Mobile uses its versioned app storage. Center support is additive. A C recording may add `center_raw.csv`; legacy L/R training/export schema must not silently become 18-channel data.

## D9 - Synchronization requires provenance

Cross-sensor timing uses saved clock observations/drift fitting and common scheduled start evidence. A saved affine map documents a mapping but is not independent proof of physical simultaneity. Never synchronize L/R/C by independently zeroing their epochs.

## D10 - One operator client per sensor set

Do not operate the same connected L/R[/C] set concurrently from mobile and Windows.

## D11 - Release/build artifacts are not source state

Packaging definitions are source-controlled; generated installers/firmware binaries/build directories remain untracked/ignored. A successful build is not an installation, flash, release or physical acceptance.

## D12 - Feature-branch safety

Current work belongs on `feature/dual-imu-coaching-analysis`. Preserve `main` and `release/main-v1.8.0`; no merge, force-push, tag, updater/release publication or repository rename without explicit user direction. Preserve unrelated `.github/workflows/release.yml` work.

## D13 - Stable version identity remains unchanged

The stable v1.8.0 product/release identity remains the release line. Experimental model and center-sensor source work does not advance stable version metadata by itself.

## D14 - Physical claims require physical evidence

Unit tests, simulated BLE and compile output can prove software/build behavior. They cannot establish real RF throughput, actual start skew, gravity orientation, range configuration, loss rate or trajectory accuracy. Those require hardware/reference measurements.

## D15 - Model defaults remain frozen until P3 acceptance

Inherited geometry/calibration values remain assumptions unless separately measured. Windows classical default and mobile M4 ONNX default remain unchanged. PyTorch residual/Slalom paths are explicitly experimental. P3 remains `blocked_by_reference_data`.

## D16 - Public source vs private research evidence

Do not publish athlete recordings, derived participant data, pseudo-GT, generated private models, absolute private paths, signing material or local evidence. `BiWheel3D/` remains a separate local research repository.

## D17 - Center data cannot silently enter the legacy model

Current L/R model feature extraction must produce exactly the same tensor with or without C samples. Any center-aware estimator gets a new explicit model/feature contract, training set and validation/final gate. Never extend the legacy tensor merely by iterating every enum role.

## D18 - Course constraints must be labeled as constraints

Slalom endpoint/heading closure uses known protocol structure. Report raw pose, constrained pose and correction magnitudes separately. A constrained endpoint near zero cannot be advertised as independent odometry accuracy.

## D19 - Runtime reproducibility is a model-selection requirement

Exploratory metrics are not accepted until the same algorithm reproduces deterministically through the intended application/runtime. Slalom course v2 is the negative precedent: numerically unstable float32 finite-difference behavior produced apparent gains that collapsed in app execution. Keep it as rejected evidence; do not resurrect its headline numbers as validated performance.

## D20 - Reference timing errors must not be learned away

If C3D/IMU alignment exhibits drift/time-scale mismatch, audit reference clock provenance before training more model complexity. A neural/calibration model must not be used to compensate an unverified reference timeline simply because that reduces a plotted error.
