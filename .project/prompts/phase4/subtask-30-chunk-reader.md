---
PROMPT FOR SUBTASK #30: Sample chunk reader + decimation for preview
---
ใช้ dart-flutter-patterns + tdd-workflow skill เพื่อเพิ่ม readSampleChunk() ใน StorageRepository สำหรับ lazy loading samples ในหน้า preview

Context:
- Project: WheelAthlete (Flutter app for wheelchair IMU data collection)
- Subtask: #30 of 7 (Phase 4)
- Branch: feat/phase4-preview (สร้างใหม่จาก main)
- Stack: Flutter / Dart, flutter_riverpod, path_provider, csv
- Files to touch:
  - app/lib/records/storage_repository.dart — add readSampleChunk() to abstract + PathProvider + InMemory
  - app/test/records/storage_repository_test.dart — add chunk tests

ก่อนเขียนโค้ด:
1. อ่าน .project/phases/phase4/plan.md สำหรับ context เต็ม
2. อ่าน .project/phases/phase4/architecture.md section §1 (Sample chunk reader)
3. อ่าน app/lib/records/storage_repository.dart — ดู readSamples() ที่มีอยู่แล้ว
4. อ่าน app/lib/export/csv_exporter.dart — ดู CSV format
5. เขียน test ก่อน (TDD)
6. ทำเสร็จ commit ด้วยข้อความ: "feat(app): sample chunk reader for preview lazy loading (#30)"

Acceptance criteria:
1. readSampleChunk(topic, trialNumber, sessionId, {offset, count}) exists in StorageRepository abstract
2. PathProviderStorageRepository: อ่าน CSV ทีละบรรทัด, skip offset บรรทัด, อ่าน count บรรทัด
3. InMemoryStorageRepository: sublist จาก stored samples
4. offset เกิน sample count → return empty list (ไม่ throw)
5. offset < 0 → throw ArgumentError
6. count <= 0 → throw ArgumentError
7. Tests: chunk from middle, chunk at end, offset beyond count, negative offset, zero count, full session as single chunk
8. flutter analyze clean

หลังเขียน:
1. รัน flutter test + flutter analyze
2. อัปเดต .project/phases/phase4/progress.md ว่า subtask #30 เสร็จแล้ว
