# Roadmap

> v0.1.0 — Data Collection MVP

## Done in v0.1.0

### Phase 1 — Data Collection & Calibration
- Firmware: IMU acquisition (MPU6886 FIFO + data-ready interrupt)
- Firmware: BLE GATT server (NimBLE) with 5 characteristics + Battery Service
- Firmware: Scheduled synchronized start + beep 3-2-1
- App: BLE scan + connect to 2 modules simultaneously
- App: Clock sync engine (offset + drift correction → UTC timeline)
- App: Realtime IMU display
- App: Recording with synchronized start
- App: CSV export + share
- Docs: BLE protocol spec + field data collection protocol

### Phase 3 — Browse & Record Hardening
- App: Protocol templates with target trial count
- App: Experiment tracker dashboard
- App: Session tags + search/filter on Browse
- App: Delete at topic / trial / session levels
- App: Quick re-record from stopped view
- App: Mark Event removed (beep + camera audio replaces it)

### Phase 4 — Session Preview & Quality
- App: Session preview page (scrub slider, accel/gyro charts, summary stats)
- App: Quality badges (good / fair / poor / unknown) from drift residual RMS
- App: Sample chunk reader for lazy loading in preview
- App: Session stats computation (mean/peak accel + gyro magnitude)
- App: Excel export (.xlsx) with separate L/R sheets
- App: UTC millisecond alignment for cross-wheel + cross-camera sync
- Firmware: Display refinements + BLE stability improvements

## Planned (not in this release)

### Phase 5 — Python ML Pipeline
- Load CSV sessions into Python
- Feature extraction (windowed stats, frequency-domain, jerk, etc.)
- Train classification/regression model for biomechanical metrics
- Model evaluation + cross-validation
- Export trained model for on-device inference

### Phase 6 — Real-time Feedback
- On-device inference using the trained model
- Real-time biomechanical metrics displayed to athlete during training
- Audio/haptic cues for technique corrections

### Phase 7 — Cloud + Multi-Athlete Dashboard
- Cloud sync of session data
- Web dashboard for multi-athlete comparison
- Coach view with aggregated metrics
- Longitudinal progress tracking

### Phase 8 — Automated Video↔IMU Alignment
- Beep detection in camera audio (find the 3-2-1 peaks)
- Automatic time offset computation between video and IMU timeline
- Visual marker detection (optional, for cross-check)
- Eliminate manual alignment

### Other planned
- **OTA firmware updates** over BLE (no USB required)
- **Multi-wheel support** (4 wheels for court sports like basketball)
- **CI/CD** — GitHub Actions for `flutter test` + `flutter analyze` + `pio test`
- **Localization** — full i18n for the app UI (currently English + Thai docs)

## Versioning

This project uses Semantic Versioning for the coordinated app, firmware, and
BLE contract:

| Version | Meaning |
|---------|---------|
| `0.x.y` | Pre-release — feature incomplete, breaking changes possible |
| `1.0.0` | First stable data-collection release |
| `1.x.y` | Backward-compatible features and reliability improvements |
| `2.0.0` | Breaking changes (data format, BLE protocol, etc.) |

Machine-learning milestones are tracked as product capabilities and do not
control the stability version of the data-collection stack.

Independent version tracks:
- **App:** `1.7.0+8` (Flutter convention: `version+buildNumber`)
- **Firmware:** `1.7.0` (shared by both hardware targets)
- **BLE Protocol:** `1.7.0` (independent of app/firmware; bump on contract changes)

## Release history

| Tag | Date | Summary |
|-----|------|---------|
| `v1.7.0` | 2026-07-25 | Stable dual-wheel reliability release — firmware 1.7.0, app 1.7.0+8, BLE 1.7.0 |
| `v0.1.0` | 2026-07-06 | Data Collection MVP (pre-release) — firmware 0.2.0, app 1.0.0+1, BLE 1.1.0 |
