# PC Version Phase 08 — Windows UI / Diagnostics Verification

Date: 2026-09-01 (Asia/Bangkok)
Branch: `codex/pc-version`

## Scope

Phase 08 adds the Windows operator shell without changing ownership of the raw
acquisition path. Python/Bleak remains responsible for BLE notifications,
packet parsing, sequence accounting, synchronization, journaling and QC.
Flutter receives only versioned localhost commands, status/health data and the
throttled preview channel.

Desktop surfaces implemented:

- Dashboard
- Connect (L/R independently, scan, RSSI, battery, MTU, configured/received rate)
- Live preview (~10 Hz, accelerometer + gyroscope)
- Record (metadata, protocol template, 50/100/200 Hz, deterministic start/stop)
- Experiments (existing template workflow reused)
- Sessions (authoritative PC `.waj` library plus existing app library)
- Diagnostics (host/firmware queue, loss, transport, clock and disk counters)
- Crash recovery, CSV derivation and diagnostic JSON export

## Reliability boundaries

- Raw 50/100/200 Hz samples do not cross into Flutter.
- The desktop record rate is written to each connected board before
  `start_record`; it is not metadata-only.
- Protocol-template ID and tags are stored in authoritative journal metadata.
- PC session summaries are written atomically beside finalized `.waj` files.
- UI status polling is 1 Hz and preview history is bounded to 240 points/side.
- RSSI is displayed but never used as the primary loss/QC signal.
- Current Bleak API does not expose a portable Windows connection interval, so
  the UI states that explicitly instead of inventing a value.

## Verification evidence

- `python -m pytest tools\pc_acquisition\tests -q` → `21 passed`.
- `python -m compileall -q tools\pc_acquisition` → clean.
- `flutter test test\desktop` → `8 passed`.
- `dart analyze lib test\desktop` → `No issues found!`.
- complete `flutter test` → `644 passed` with the current production code.
- `flutter build apk --release` → green; APK ≈ `52.9 MB`.

The PC tests include authoritative protocol-template/tag metadata coverage. The
desktop tests include the rule that the requested recording rate is configured
on every connected board before the daemon receives `start_record`.

## Known environment blocker

`flutter build windows --release` cannot be completed on this host because the
Flutter-supported Visual Studio Desktop development with C++ toolchain is not
installed. This is kept separate from code-level verification and no system
component was installed automatically.
