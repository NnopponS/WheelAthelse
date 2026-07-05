---
PROMPT FOR SUBTASK #33: Session preview page (chart + scrub + stats)
---
ใช้ dart-flutter-patterns + tdd-workflow skill เพื่อสร้าง SessionPreviewPage ที่แสดง IMU chart + scrub slider + summary stats

Context:
- Project: WheelAthlete (Flutter app for wheelchair IMU data collection)
- Subtask: #33 of 7 (Phase 4)
- Branch: feat/phase4-preview (ต่อจาก #30 + #31)
- Stack: Flutter / Dart, flutter_riverpod, fl_chart
- DEPENDS ON: #30 (readSampleChunk) + #31 (SessionStats) — both must be complete
- Files to create:
  - app/lib/ui/session_preview_page.dart — full preview page
  - app/lib/state/preview_providers.dart — Riverpod providers
  - app/test/ui/session_preview_page_test.dart

ก่อนเขียนโค้ด:
1. อ่าน .project/phases/phase4/plan.md สำหรับ context เต็ม
2. อ่าน .project/phases/phase4/architecture.md section §4 (Session preview page)
3. อ่าน app/lib/widgets/imu_chart.dart — ImuChart + ImuChartBuffer (reuse!)
4. อ่าน app/lib/records/session_model.dart — BufferedSample, SessionMeta
5. อ่าน app/lib/records/session_stats.dart (from #31) — SessionStats + Calculator
6. อ่าน app/lib/records/storage_repository.dart — readSampleChunk (from #30)
7. เขียน test ก่อน (TDD)
8. ทำเสร็จ commit ด้วยข้อความ: "feat(app): session preview page with chart + scrub + stats (#33)"

Acceptance criteria:
1. SessionPreviewPage is a ConsumerStatefulWidget
2. Shows: AppBar (session ID + topic/trial), summary stats card, scrub slider, wheel selector (Left/Right/Both), accel chart, gyro chart
3. initState: loads first chunk (offset 0, count 500) + computes stats
4. Scrub slider: 0 to durationMs, debounced 200ms, loads chunk around scrub position
5. Chart: reuses ImuChart widget, converts BufferedSample.reading → ImuReading
6. Window: 5s around scrub position (2.5s before + 2.5s after), or full if shorter
7. Wheel selector filters samples by WheelSide (both = all, left = left only, right = right only)
8. Loading indicator while chunk loads
9. preview_providers.dart: sampleChunkProvider (FutureProvider family), sessionStatsProvider
10. Tests: page renders stats, scrub updates chart, wheel selector filters, loading state, empty session
11. flutter analyze clean

หลังเขียน:
1. รัน flutter test + flutter analyze
2. อัปเดต .project/phases/phase4/progress.md ว่า subtask #33 เสร็จแล้ว
