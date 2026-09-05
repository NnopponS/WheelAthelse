# WheelAthlete — Current Decisions

Updated: 2026-09-05

Only active decisions are kept here. Superseded phase decisions belong in Git history, not in the current project state.

## D1 — Two user-facing apps only

WheelAthlete has two product applications:

- Flutter mobile app for iOS/Android
- Python Windows app using PySide6

Flutter Windows, Flutter Web, and the old Tkinter GUI are retired and removed.

## D2 — Shared BLE protocol

Both clients use the same firmware BLE contract in `docs/ble-protocol.md`. Firmware changes that affect packet layout, commands, characteristics, or semantics require a coordinated protocol/version update.

## D3 — Dual-wheel acquisition

Left and right wheel sensors are acquired together. Sequence counters, loss telemetry, synchronization, and per-wheel diagnostics must remain visible. RSSI is context, not proof of data integrity.

## D4 — Sampling rates

Supported acquisition rates are 50, 100, and 200 Hz. A recording configuration must be applied to the connected board(s), not stored as metadata only.

## D5 — Mobile owns BLE directly

The Flutter mobile app uses `flutter_blue_plus` and remains independent from the Windows acquisition daemon. Mobile recording/export behavior must continue to work without any PC process.

## D6 — Windows GUI does not own authoritative raw data

On Windows, `tools.pc_acquisition` owns BLE, synchronization, raw journal writes, QC, and recovery. `tools.pc_gui` receives control/state/diagnostics and bounded preview traffic over localhost IPC.

This process boundary is a reliability requirement, not an implementation detail.

## D7 — Windows authoritative format is `.waj`

The append-only `.waj` journal is the source of truth for Windows recordings. CSV is a derived export artifact. Incomplete journals must remain recoverable.

## D8 — Mobile storage remains mobile-native

The mobile app stores its session data under its app documents area using topic/trial/session organization and versioned metadata. Existing mobile data compatibility must not be broken merely to match the Windows `.waj` implementation.

## D9 — Synchronization

Cross-wheel time mapping uses low-RTT clock synchronization and drift fitting. Recording start is scheduled against a common client timeline and verified with firmware lifecycle acknowledgements. Exported synchronized timestamps must retain clear provenance.

## D10 — One operator client per sensor pair

Do not attempt to operate the same two BLE peripherals from the mobile and Windows clients simultaneously. A pair should be controlled by one operator client at a time.

## D11 — Packaging is source-controlled, artifacts are not

Windows installer definitions live in `packaging/windows/`. Generated `build/` and `release/` artifacts remain ignored by Git.

## D12 — Branch safety

PC-version development remains on `codex/pc-version`. Do not merge, rebase onto, reset, force-update, or push changes into `main` unless the user explicitly requests it.

## D13 — Release coordination

Current release line is `v1.8.0`:

- Mobile: `1.8.0+9`
- Firmware: `1.8.0`
- BLE protocol: `1.8.0`
- Windows package: `1.8.0`

Version consistency is checked by automated tests.

## D14 — Physical claims require physical evidence

Automated tests and simulation may establish software behavior, but must not be used to claim real RF throughput, real two-wheel start skew, or hardware-level loss performance. Those require the physical two-XIAO acceptance matrix.
