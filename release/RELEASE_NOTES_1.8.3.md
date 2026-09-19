# WheelAthlete 1.8.3

WheelAthlete 1.8.3 is a focused Windows application update enhancing synchronized acquisition timing, countdown audio fidelity, and recording quality control metadata visibility. Firmware remains at 1.8.2 and BLE protocol at 1.8.0.

## Highlights

- **Synchronized Acquisition Audio & Countdown Overhaul**:
  - Direct, clear countdown visual progression (`5`, `4`, `3`, `2`, `1`, `START!`) without distracting calibration messages.
  - In-memory 16-bit PCM WAV sine tone generator (`700 Hz` interval beeps, `1200 Hz` start tone) paired with a persistent background audio queue worker.
  - Automatic audio subsystem pre-warming on application launch and recording trigger, preventing Windows DAC power-saving sleep truncation and ensuring every tick is reliably audible.
  - Independent T0 hardware timing timer prevents event races from canceling the start cue tone.
- **Acquisition QC Metadata Display**:
  - Final QC summary card now explicitly displays the recorded **Experiment** (topic) and **Trial** number alongside the athlete name, duration, and QC rating (e.g. `Final QC: GOOD • 12.4 s` / `Experiment: Sprint • Trial 1 • Athlete: Athlete A`).
  - Metadata is reliably preserved and propagated through acquisition daemon IPC, LiveController, and DemoController.
- **Verification & Testing**:
  - Full Windows desktop suite verified with **215 passed** tests.
  - Corrected model selector logic in tests for 3-IMU role validation.
  - Project publication and staged hygiene verified with zero errors.

## Verification boundary

Consolidation and release verification passed **215/215** active Windows unit and GUI tests, **4/4** Windows packaging-layout tests, release-manifest tests, Python compile checks, and project publication hygiene.

## Trust status

This release remains **source-only** until a trusted commercial Windows code signing identity is configured. No installer, portable archive or `latest.json` is published without `public_release_ready=true`.

## Publication scope

The release publishes the integrated root source only. It does not publish private research recordings, local evidence, signing material, the separate `BiWheel3D` repository, or mobile release binaries.
