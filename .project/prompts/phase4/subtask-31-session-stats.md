---
PROMPT FOR SUBTASK #31: Session stats computation (pure logic)
---
ใช้ dart-flutter-patterns + tdd-workflow skill เพื่อสร้าง SessionStats model + SessionStatsCalculator แบบ pure logic

Context:
- Project: WheelAthlete (Flutter app for wheelchair IMU data collection)
- Subtask: #31 of 7 (Phase 4)
- Branch: feat/phase4-preview (สร้างใหม่จาก main — independent จาก #30)
- Stack: Flutter / Dart
- Files to create:
  - app/lib/records/session_stats.dart — SessionStats model + SessionStatsCalculator
  - app/test/records/session_stats_test.dart

ก่อนเขียนโค้ด:
1. อ่าน .project/plan-phase4.md สำหรับ context เต็ม
2. อ่าน .project/architecture-phase4.md section §2 (Session stats)
3. อ่าน app/lib/records/session_model.dart — BufferedSample + SessionMeta
4. อ่าน app/lib/ble/imu_packet.dart — ImuReading (ax/ay/az/gx/gy/gz)
5. เขียน test ก่อน (TDD)
6. ทำเสร็จ commit ด้วยข้อความ: "feat(app): session stats computation pure logic (#31)"

Acceptance criteria:
1. SessionStats model with fields: sampleCount, durationMs, dropCount, syncQualityMs, meanAccelMagnitude, peakAccelMagnitude, meanGyroMagnitude, peakGyroMagnitude
2. SessionStatsCalculator.compute(List<BufferedSample> samples, SessionMeta meta) returns SessionStats
3. accel magnitude = sqrt(ax² + ay² + az²)
4. gyro magnitude = sqrt(gx² + gy² + gz²)
5. mean + peak computed from provided samples
6. dropCount from meta (if available) else 0
7. syncQualityMs = max of left/right driftResidualRmsMs (null if both null)
8. Empty samples → zero stats (no NaN, no crash)
9. Tests: basic stats, empty samples, single sample, large sample list, both wheels mixed
10. flutter analyze clean

หลังเขียน:
1. รัน flutter test + flutter analyze
2. อัปเดต .project/progress-phase4.md ว่า subtask #31 เสร็จแล้ว
