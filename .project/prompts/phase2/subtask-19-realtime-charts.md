---
PROMPT FOR SUBTASK #19: Realtime IMU line charts (fl_chart, per axis)
---
Use `dart-flutter-patterns` + `tdd-workflow` + `latency-critical-systems` + `verification-loop` for this subtask.

Context:
- Feature: Phase 2 app data (Issue #3)
- Branch: `feat/phase2-app-data-issue-3`
- Subtask: #19
- Goal: Add realtime scrolling line charts to the Live screen — one chart for ax/ay/az and one for gx/gy/gz per wheel, rolling ~5s window, per-axis colors from the design system. Keep numeric tiles as a compact summary.
- Files: `app/lib/ui/live_page.dart`, `app/lib/widgets/imu_chart.dart` (NEW), `app/lib/state/imu_providers.dart`, `app/lib/theme/app_palette.dart`, `app/pubspec.yaml` (fl_chart already present), `app/test/...` (new tests)
- Stack: Flutter / Dart, flutter_riverpod, fl_chart

Steps:
1. Read `.project/plan.md` (Phase 2) + `.project/architecture.md` + `.project/progress.md`.
2. Read `app/lib/state/imu_providers.dart` — `WheelImuState.latest` holds only the latest reading. Add a rolling ring buffer of recent readings (~5s at the active rate) to the state, or a dedicated `ImuChartBufferNotifier`.
3. latency-critical-systems: decimate/downsample before plotting (cap ~50-100 pts per axis) to avoid jank at 100 Hz; never plot every sample.
4. TDD: write tests first for the chart buffer (ring buffer trim to window, decimation logic) — pure logic, no Flutter.
5. Implement `ImuChart` widget (fl_chart `LineChart`) taking a list of readings + axis colors; two charts per wheel (accel, gyro).
6. Update `LivePage` `_WheelPanel`: show charts above the numeric tile summary; keep tiles compact.
7. Verify: `flutter analyze` clean; `flutter test` green; widget test that `ImuChart` renders with mock data; no pumpAndSettle timeout (avoid infinite animation).
8. Commit: `feat(app): realtime IMU line charts (#19)`
9. Update `.project/progress.md` row #19.

Definition of done: Live screen shows scrolling per-axis accel + gyro charts per wheel, rolling ~5s, no jank at 100 Hz; numeric tiles retained; unit + widget tested; flutter analyze + test green.
