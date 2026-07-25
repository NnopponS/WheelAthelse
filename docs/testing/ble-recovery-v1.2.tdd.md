# BLE Recovery and Live Control v1.2 — Verification Evidence

## User journeys

- Start and stop connected boards from Live without creating a recording.
- Recover notification sequence gaps from bounded firmware history.
- Hide connected boards from subsequent scans and publish battery on connect.
- Export exactly one topic as a named folder with trial CSVs and metadata.

## Evidence

| Guarantee | Test or command | Result |
|---|---|---|
| Replay requests are encoded and recovered samples are ordered/deduplicated across uint32 wrap | `flutter test test/state/sample_recovery_test.dart test/ble/control_command_test.dart` | PASS |
| Live sends START/STOP and handles both wheel streams | `flutter test test/ui/live_page_test.dart` | PASS |
| Connected scan filtering and initial battery publication | `flutter test test/state/connection_manager_test.dart test/state/battery_rssi_test.dart` | PASS |
| Topic/trial filenames, atomic topic folder, metadata, and manifest | `flutter test test/export/export_actions_test.dart test/ui/browse_page_test.dart` | PASS |
| App, firmware, and protocol versions agree | `flutter test test/version_consistency_test.dart` | PASS |
| Complete Flutter regression suite | `flutter test --coverage -r silent` | PASS, 597 tests |
| Business/application line coverage | `coverage/lcov.info` | 81.61% (4012/4916) |
| Dart static analysis | `dart analyze lib` | PASS, no issues |
| M5 firmware host behavior tests | `python -m pytest test -q` | PASS, 115 tests |
| M5 left/right release firmware | `pio run -e left -e right` | PASS |
| Xiao left/right release firmware | `pio run -e left -e right` | PASS |
| Android release package | `flutter build apk --release` | PASS |

## RED/GREEN notes

- The first complete Flutter regression run exposed three failures in legacy
  immediate-gap behavior after introducing the reorder buffer. The hub was
  corrected to release unsupported legacy gaps immediately and route malformed
  packets through the stream error state; the focused tests and complete suite
  then passed.
- The first M5 build exposed that NimBLE 1.4 returns `void` from `notify()`.
  The implementation was adapted to use sequence replay as the delivery proof
  on M5; Xiao retains the local boolean notify-failure counter. Both targets
  then built successfully.

## Known verification gap

The automated suite cannot perform the physical 20-cycle dual-board acceptance
or sustained 100/200 Hz radio test. Those checks require both real boards and
must be completed before declaring hardware acceptance.

## BLE stop/export follow-up TDD

| Guarantee | Test/validation | Result |
|---|---|---|
| Start/Stop cannot be toggled while an operation is starting or stopping | `test/state/live_acquisition_guard_test.dart` | PASS |
| Live Stop remains stable through the UI path | `flutter test test/ui/live_page_test.dart` | PASS |
| Session sharing produces a topic/trial/date CSV name | `test/export/export_providers_test.dart` | PASS |
| Trial export combines sessions into one named CSV | `test/export/export_providers_test.dart` | PASS |
| Full regression suite remains green after event-driven acknowledgments | `flutter test` | PASS, 599 tests |
| Static analysis after BLE serialization changes | `dart analyze lib` | PASS, no issues |

Implementation notes: Live and recording acquisition now mark devices as
acquiring so RSSI polling is suppressed; control writes are serialized per
device; START/STOP acknowledgment waits are completed by Sync events rather
than a 20 ms polling loop; and share exports no longer use `session_<id>` as
their primary filename.
