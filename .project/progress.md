# WheelAthlete — Current Progress

Updated: 2026-09-05 (Asia/Bangkok)
Branch: `codex/pc-version`

## Current status

### Flutter Mobile App

- Product target: iOS + Android only
- Direct dual-wheel BLE acquisition remains intact
- Session recording, browsing, preview, tags/templates, QC, and export remain implemented
- Windows/Web platform targets removed from the Flutter product
- Current release metadata: `1.8.0+9`

### Python Windows App

- PySide6 six-page research UI implemented
- Separate acquisition daemon owns BLE/raw-data path
- Auto-start/reuse of localhost daemon implemented
- `.waj` journal, recovery, QC, diagnostics, CSV export implemented
- Source launcher: `run_python_pc_app.bat`
- Portable EXE + Inno Setup packaging maintained under `packaging/windows/`
- Current package version: `1.8.0`

### Firmware / protocol

- M5StickCPlus2 and XIAO nRF52840 Sense targets maintained
- Left/right configs and 50/100/200 Hz acquisition supported
- Reliability telemetry, replay/recovery support, lifecycle acknowledgements, and synchronized-start support implemented
- Coordinated firmware/protocol version: `1.8.0`

## Repository cleanup — 2026-09-05

Completed:

- removed legacy `run_gui_app.bat`, Tkinter/Matplotlib GUI, and old direct-BLE PC CSV client
- removed Flutter Windows runtime, UI/backend, and tests
- removed Flutter Web scaffold
- made `app/lib/main.dart` mobile-only
- moved Windows packaging sources to `packaging/windows/`
- reduced `.project` to six canonical current-state/history documents
- removed duplicated phase plans/prompts/trackers that are already preserved by Git history
- refreshed root/app/wiki/data-collection documentation around the two supported products
- aligned product/mobile/firmware/protocol/Windows metadata to v1.8.0 / mobile build +9
- fixed mobile runtime/export metadata that still emitted v1.7.0 values
- added version-consistency coverage for runtime metadata and Windows packaging

## Verification — 2026-09-05

Passed on the current source tree:

- `flutter test` — **637 tests passed**
- `flutter analyze --no-pub` — **No issues found**
- coordinated version consistency test — passed
- `python -m pytest tools/pc_acquisition/tests tools/pc_gui/tests -q` — **54 passed**
- `python -m compileall -q tools/pc_acquisition tools/pc_gui` — passed
- M5StickCPlus2 PlatformIO `left` — **SUCCESS**
- M5StickCPlus2 PlatformIO `right` — **SUCCESS**
- XIAO nRF52840 Sense PlatformIO `left` — **SUCCESS**
- XIAO nRF52840 Sense PlatformIO `right` — **SUCCESS**
- M5 firmware Python tests — passed
- XIAO firmware Python tests — passed
- Windows packaging build — **Successful compile**
  - `release/WheelAthlete-1.8.0-portable.zip`
  - `release/WheelAthleteSetup-1.8.0.exe`
  - bundled `WheelAthleteDaemon.exe` verified inside the packaged GUI tree
- `git diff --check` — clean
- exact tracked search for `1.7.0+8` now finds historical release documentation only

Generated `build/` and `release/` artifacts are intentionally ignored by Git and are not part of the source commit.

## Physical blocker

The prepared two-XIAO physical acceptance matrix is still the gate for claims about real RF throughput, actual 0.5/2/5 m loss behavior, negotiated controller behavior, and measured left/right start skew. Do not mark those claims as verified without attached hardware evidence.
