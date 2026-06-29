# Subtask #9 — TDD Evidence Report

## Scope
Flutter: CSV export (synced/resampled) + folder hierarchy + share + browse page.

## What was built

### CSV Exporter (pure, no I/O)
- `app/lib/export/csv_exporter.dart`:
  - `CsvExporter.toCsvString(samples)` — converts samples to CSV string.
  - `CsvExporter.writeToSink(sink, samples)` — streams CSV to a `StringSink`
    for large files (avoids building entire string in memory).
  - Schema per architecture.md §3:
    `seq,wheel,timestamp_app_ms,timestamp_device_us,timestamp_synced_ms,ax,ay,az,gx,gy,gz,marker`
  - Samples sorted by `timestamp_synced_ms` (L before R at same timestamp).
  - `wheel` column is `L` or `R`.
  - `marker` is `1` or `0`.
  - Double values formatted without trailing zeros (`1.0` → `1`, `1.50` → `1.5`).

### Resampler (pure, no I/O)
- `app/lib/export/resampler.dart`:
  - `Resampler.resample(samples, gridIntervalMs)` — linear interpolation of
    both wheels onto a common time grid (architecture.md §4.6).
  - No extrapolation: grid points outside a wheel's range are skipped.
  - Interpolates all 6 axes (ax, ay, az, gx, gy, gz) independently.
  - `marker` flag set if any sample in the interpolation window has marker.
  - `seq` is synthetic grid index (0, 1, 2, ...).
  - Binary search for bracketing pair.

### Export Providers (Riverpod)
- `app/lib/export/export_providers.dart`:
  - `ExportNotifier` — manages export state:
    - `exportSession(topic, trial, sessionId, {resample, gridIntervalMs})` —
      reads samples from storage, optionally resamples, writes CSV via
      `StorageRepository.writeSessionCsv`, returns file path.
    - `exportTrial(topic, trial)` — exports all sessions in a trial.
    - `exportTopic(topic)` — exports all sessions in all trials of a topic.
    - `shareSession/shareTrial/shareTopic` — shares via `share_plus`
      `SharePlus.instance.share()` (v13 API).

### Storage Repository Extensions
- `app/lib/records/storage_repository.dart`:
  - Added: `readSamples`, `listTrials`, `getSessionCsvPath`,
    `getTrialDirPath`, `getTopicDirPath`, `writeSessionCsv`.
  - `PathProviderStorageRepository`: real file I/O for all new methods.
  - `InMemoryStorageRepository`: in-memory fake for tests.

### Browse Page (UI)
- `app/lib/ui/browse_page.dart`:
  - Three-level navigation: topic list → trial list → session list.
  - `_TopicListView` — folder icons, empty state with "No topics yet".
  - `_TrialListView` — `trial_NN` labels, back button.
  - `_SessionListView` — `SessionListItem` widgets with share buttons,
    sample count, marker count, sync quality.
- `app/lib/ui/live_page.dart`: added Browse icon button in AppBar.

### Dependencies
- Added `csv` and `share_plus: ^13.2.0` to pubspec.yaml.

## TDD workflow
1. RED: `test/export/csv_exporter_test.dart` (11 tests) — header schema,
   empty samples, single row, marker flag, wheel L/R, sorted by synced_ms,
   L/R interleaved, double formatting, streaming sink, negative timestamps,
   uint32 max seq.
2. GREEN: `csv_exporter.dart` — all 11 pass.
3. RED: `test/export/resampler_test.dart` (10 tests) — empty, perfect grid,
   linear interpolation, both wheels, grid start, no extrapolation, all 6
   axes, marker flag, synthetic seq, non-uniform intervals.
4. GREEN: `resampler.dart` — all 10 pass.
5. RED: `test/export/export_providers_test.dart` (5 tests) — export session,
   resample, not found, export trial, export topic.
6. GREEN: `export_providers.dart` — all 5 pass.
7. RED: `test/ui/browse_page_test.dart` (7 tests) — topic list, navigate to
   trials, navigate to sessions, sample/marker counts, share buttons, back
   button, empty state.
8. GREEN: `browse_page.dart` — all 7 pass.

## Test results
- `flutter analyze`: **clean** (0 issues)
- `flutter test`: **282/282 PASS** (was 249 before #9; +33 new tests)
  - `test/export/csv_exporter_test.dart`: 11 tests
  - `test/export/resampler_test.dart`: 10 tests
  - `test/export/export_providers_test.dart`: 5 tests
  - `test/ui/browse_page_test.dart`: 7 tests
- Coverage (new files):
  - `lib/export/csv_exporter.dart`: **97.1%** (33/34 lines)
  - `lib/export/resampler.dart`: **98.5%** (66/67 lines)
  - `lib/export/export_providers.dart`: **60.8%** (31/51 lines)
  - `lib/ui/browse_page.dart`: **85.8%** (91/106 lines)
  - `lib/records/storage_repository.dart`: **92.5%** (49/53 testable lines)

## Bugs caught by TDD
- **share_plus API deprecation**: `Share.shareXFiles()` is deprecated in
  v13. Fixed by using `SharePlus.instance.share(ShareParams(...))`.
- **In-memory storage file path**: `exportSession` tried to write to `File()`
  but `InMemoryStorageRepository` returns `memory://` paths. Fixed by adding
  `writeSessionCsv` to the `StorageRepository` interface.
- **Resampler no-extrapolation**: initial test expected extrapolation at grid
  boundaries. Fixed test to expect skips for out-of-range grid points.
- **Unused imports**: `ble_repository.dart`, `device_info.dart`, `wheel_id.dart`,
  `session_model.dart`, `storage_repository.dart` in test files. Removed.
- **prefer_const_constructors**: `BufferedSample` in tests could be `const`.
  Fixed.

## Skills used
dart-flutter-patterns, tdd-workflow, verification-loop
