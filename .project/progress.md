# Progress Tracker

| # | Subtask | Skill | Status | Started | Completed | Commit |
|---|---------|-------|--------|---------|-----------|--------|
| 1 | Scaffolding + monorepo + git/GitHub + BLE/sync/folder protocol spec | git-workflow | completed | 2026-06-28 | 2026-06-28 | f10ffd6 |
| 2 | Firmware: IMU read + display + serial debug | cpp-coding-standards | completed | 2026-06-28 | 2026-06-28 | c8301ce |
| 3 | Firmware: BLE GATT + time-sync support | cpp-coding-standards | pending | - | - | - |
| 4 | Flutter: design system / theme / components (UI สวย) | impeccable + ui-ux-pro-max | completed | 2026-06-28 | 2026-06-28 | 9583327 |
| 5 | Flutter: scan + connect 2 devices + state | dart-flutter-patterns | pending | - | - | - |
| 6 | Flutter: parse packet + realtime display | dart-flutter-patterns | pending | - | - | - |
| 7 | Flutter: clock sync engine (offset/drift/common timeline) | dart-flutter-patterns | pending | - | - | - |
| 8 | Flutter: recording + Mark Event + folder topic/trial | dart-flutter-patterns | pending | - | - | - |
| 9 | Flutter: CSV export (synced) + folder hierarchy + share | dart-flutter-patterns | pending | - | - | - |
| 10 | Docs: data-collection protocol + field test (verify sync) | tdd-workflow | pending | - | - | - |

## Notes / Blockers
- 2026-06-28: subtask #1 done. Repo: https://github.com/NnopponS/WheelAthelse (private)
  - BLE protocol v1.0.0 in docs/ble-protocol.md (UUIDs, packet layout, control/sync/info, CSV schema, folder model)
  - Next: #2 (firmware IMU) and #4 (Flutter design system) can run in parallel after #1
- 2026-06-28: subtask #4 done. Flutter app scaffolded (com.wheelsense, android+ios).
  - deps: google_fonts, fl_chart. Design system in app/lib/theme/ (palette, dimens, typography,
    WheelSenseColors ThemeExtension for L=blue/R=orange + semantic, light+dark high-contrast ThemeData).
  - components in app/lib/widgets/: ConnectionCard, LiveMetricTile, PrimaryActionButton,
    MarkEventButton, SessionListItem, StatusBadge, EmptyState, LoadingState, ErrorState.
  - app/lib/ui/showcase_page.dart = living style guide (home), theme toggle, animated mock metrics.
  - verify: `flutter analyze` clean; widget test passes (renders + theme toggle). UI not wired to BLE (mock).
  - Next: #5 (BLE scan + connect 2 devices) reuses theme + ConnectionCard.
