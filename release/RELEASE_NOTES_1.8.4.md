# WheelAthlete 1.8.4

WheelAthlete 1.8.4 rebuilds the Windows application from the stable v1.8.3 baseline. M5StickC Plus2 and XIAO nRF52840 firmware source is restored from the supplied v1.8.3 snapshot; firmware identifiers remain v1.8.2 and BLE protocol remains v1.8.0. The frozen default trajectory model and mobile source are unchanged.

## Windows application

- Restored the orbitable 3D trajectory view with dynamic equal-distance XYZ scaling. XY-only models explicitly report that Z is unavailable.
- Added managed import for WheelAthlete CSV exports. Imports are copied into the app-managed library; undated files prompt for a date, and imported sessions can be re-exported through Results.
- Moved CSV writes off the GUI thread. Single and batch exports display progress and completion or error state, and existing files are never overwritten.
- Separated current-recording packet/loss counters from lifetime Diagnostics counters. Diagnostics reports Windows build and Bluetooth adapter driver details while removing user paths and device/session identity.
- App close now offers `Stop & close` or `Cancel` during a recording, finalizes the journal, and waits for the daemon shutdown acknowledgement. Failure keeps the window open.
- Added opt-in cleanup choices for portable application files and managed WheelAthlete data. Setup cleanup choices are unchecked by default and confirm before deleting data.

## Acceptance limits

- Firmware queue/backlog changes were not added. No cross-computer BLE stress result is claimed; repeat the same-board test on multiple Windows Bluetooth adapters before accepting transport behavior.
- Physical sensor orientation, simultaneous L/R/C timing, and trajectory accuracy remain separate hardware/reference acceptance gates.
- Public Windows binaries remain blocked until the trusted signing gate passes. The public release is source-only and contains no mobile assets.

## Verification

See [`.project/STATUS.md`](../.project/STATUS.md) for the exact software, firmware host-test, and build results for this release.
