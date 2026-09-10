# WheelAthlete development milestones

Updated: 2026-09-08. This is a compact chronology; Git and phase files contain implementation detail.

## Stable data-collection line

- `v0.1.0` (2026-07-06): first usable dual-wheel data-collection MVP.
- `v1.7.0` (2026-07-25): stable dual-wheel reliability release.
- `v1.8.0`: current stable release identity across maintained product components; experimental September work does not advance it by itself.

## Windows acquisition evolution

Major historical milestones included:
- headless dual-board ingestion,
- clock sync + scheduled start/lifecycle acknowledgement,
- append-only `.waj` + recovery/QC/derived CSV,
- physical-acceptance harness preparation,
- Python/PySide6 Research Edition,
- Windows installer/update packaging.

Retired Flutter-Windows/Tkinter experiments remain in Git history rather than current architecture.

## 2026-09-05 - Product consolidation

The supported product surface was reduced to:
- Flutter mobile Android/iOS,
- Python/PySide6 Windows,
- M5StickC Plus2 firmware,
- XIAO nRF52840 Sense firmware.

Duplicated project trackers and retired UI paths were removed/archived.

## 2026-09-06 - Formal source hierarchy

The repository was organized into `applications/`, `hardware_firmware/`, `docs/`, `.project/` and portable verification tooling. Windows launch/package documentation was aligned with the maintained architecture.

## 2026-09-07/08 - P0/P1 evaluation repair

Lag/crop/source-time/reference bookkeeping was audited and made reproducible. Corrected evaluation preserved explicit coverage/exclusions. Result: evaluation trust improved, but independent final/reference evidence remained missing.

## 2026-09-08 - P2 L/R physics diagnostics

Zero-delay and one-wheel center-speed physics were tested without changing defaults. Supported-subinterval improvements and severe full-cache Slalom counterexamples were both retained. Result: no production selection.

## 2026-09-08 - P4/P5/P6 offline coaching contract

Windows/mobile gained a common time/quality/result language, native full-session cursor/window review and create-only export. Mobile correctly continued to expose only what the M4 XY model can provide.

## 2026-09-08 - Experimental PyTorch Residual v1

A residual BiGRU was trained over the L/R physics baseline and integrated into Windows as an explicit research choice. Runtime/research numerical parity was checked. The model improved historical local validation but remained blocked from promotion by reference/final-data requirements and Slalom drift.

## 2026-09-08 - Research dataset catalog and Qualisys audit

`BiWheel3D/data/datasets/` became the non-destructive research catalog. The Sep-5 Qualisys audit established that all 19 dynamic archived C3Ds have no point trajectories (`POINT.USED=0`). Generated pseudo markers were explicitly labeled do-not-train/do-not-score.

## 2026-09-08 - Slalom full-course diagnosis and Course v1

GT-vs-model full-trajectory/turn review showed heading/yaw-waveform error accumulating after U-turns. Course v1 used the declared fixed-course return-to-start protocol while keeping PyTorch weights frozen. `SL_04` full-cache ATE/heading changed from about `0.790 m / 21.67 deg` raw to `0.219 m / 4.53 deg` constrained. The imposed endpoint closure was explicitly not treated as independent odometry evidence.

## 2026-09-08 - Slalom v2 rejected

A per-turn numerical optimizer produced attractive exploratory values but did not reproduce through the app because float32 finite-difference sensitivity collapsed into numerical noise. The candidate was retained as rejected evidence rather than promoted.

## 2026-09-08 - Slalom Calibrated Course v3

A deterministic replacement kept residual-v1 weights frozen and added small train-derived linear yaw/speed calibration, sign-aware turn detection and guarded course closure. Formal `SL_04` validation reached **ATE `0.179216 m` / heading RMSE `3.57882 deg`**; historical test remained unopened and non-SL validation remained exact no-op. P3 still remained blocked for general promotion.

## 2026-09-08 - Optional chair-center IMU source support

The user authorized adding optional center role `C` (`0x43`) for future experiments with +Z pointing down toward the floor.

Source support was implemented across:
- XIAO center firmware with yellow RGB blink/heartbeat,
- M5 center firmware with yellow identity + blinking `C` glyph,
- Windows L/R/C acquisition, journal v2, preview/export,
- Flutter L/R/C acquisition, schema/export/preview.

Current trajectory models still consume L/R only and regression tests enforce exact legacy tensor invariance to C. Both center firmware targets compile successfully, but no center board was flashed in this source pass.

## Current frontier

The next substantive evidence is physical center bench acceptance and new synchronized L/R/C + valid moving C3D capture. Only then should the project evaluate whether a center-aware model improves over the frozen two-hub baseline.
