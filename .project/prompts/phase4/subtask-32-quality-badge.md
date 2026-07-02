---
PROMPT FOR SUBTASK #32: Quality badge color thresholds (pure logic)
---
ใช้ dart-flutter-patterns + tdd-workflow skill เพื่อสร้าง SyncQuality enum + QualityBadge pure logic

Context:
- Project: WheelAthlete (Flutter app for wheelchair IMU data collection)
- Subtask: #32 of 7 (Phase 4)
- Branch: feat/phase4-preview (สร้างใหม่จาก main — independent จาก #30, #31)
- Stack: Flutter / Dart
- Files to create:
  - app/lib/records/quality_badge.dart — SyncQuality enum + QualityBadge
  - app/test/records/quality_badge_test.dart

ก่อนเขียนโค้ด:
1. อ่าน .project/plan-phase4.md สำหรับ context เต็ม
2. อ่าน .project/architecture-phase4.md section §3 (Quality badge)
3. อ่าน .project/context-phase4.md D25 สำหรับ thresholds
4. อ่าน app/lib/records/session_model.dart — driftResidualRmsMs fields
5. เขียน test ก่อน (TDD)
6. ทำเสร็จ commit ด้วยข้อความ: "feat(app): quality badge color thresholds (#32)"

Acceptance criteria:
1. enum SyncQuality { good, fair, poor, unknown }
2. QualityBadge.fromDriftRms(double? driftRmsMs) returns SyncQuality
3. Thresholds: good < 2ms, fair 2-5ms, poor > 5ms, unknown = null
4. QualityBadge.color(SyncQuality, BuildContext) returns Color (green/amber/red/grey)
5. QualityBadge.fromMeta(SessionMeta meta) returns SyncQuality — uses max of left/right drift
6. Tests: all thresholds, null, exactly 2ms (fair), exactly 5ms (fair), negative (treat as good), fromMeta with both wheels, fromMeta with one null
7. flutter analyze clean

หลังเขียน:
1. รัน flutter test + flutter analyze
2. อัปเดต .project/progress-phase4.md ว่า subtask #32 เสร็จแล้ว
