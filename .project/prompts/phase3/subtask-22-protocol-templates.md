---
PROMPT FOR SUBTASK #22: Protocol template model + repository + Riverpod providers
---
ใช้ dart-flutter-patterns skill เพื่อสร้าง Protocol Template system (model + storage + providers)

Context:
- Project: WheelAthlete
- Subtask: #22 of #27 (Phase 3, Issue #5)
- Branch: feat/phase3-protocols
- Stack: Flutter / Dart, flutter_riverpod, path_provider
- Files to create:
  - app/lib/records/protocol_template.dart (ProtocolTemplate model)
  - app/lib/records/protocol_repository.dart (abstract + PathProviderProtocolRepository + InMemoryProtocolRepository)
  - app/lib/state/protocol_providers.dart (Riverpod providers)
- Files to modify:
  - app/lib/main.dart or wherever storageRepositoryProvider is defined (add protocolRepositoryProvider)
- Acceptance criteria:
  1. ProtocolTemplate model: id, name, description?, topicName, targetTrialCount, sampleRateHz, createdAt
  2. ProtocolRepository abstract: listTemplates(), createTemplate(), updateTemplate(), deleteTemplate(), getTemplate(id)
  3. PathProviderProtocolRepository: stores templates as protocols.json in app docs dir (alongside WheelAthleteData/)
  4. InMemoryProtocolRepository: for tests (same pattern as InMemoryStorageRepository)
  5. Riverpod providers: protocolRepositoryProvider, protocolTemplatesProvider (FutureProvider), protocolTemplateNotifierProvider (Notifier for CRUD)
  6. toJson/fromJson for ProtocolTemplate
  7. Tests: model serialization, repository CRUD (InMemory), provider tests
  8. flutter analyze clean

Notes:
- Follow the exact same pattern as StorageRepository (abstract + PathProvider impl + InMemory impl)
- protocols.json format: { "templates": [ {template}, ... ] }
- id can be DateTime.now().millisecondsSinceEpoch.toRadixString(16) (same as sessionId pattern)
- No UI in this subtask — pure model + storage + providers

ก่อนเขียนโค้ด:
1. อ่าน .project/plan-phase3.md สำหรับ context เต็ม
2. อ่าน .project/architecture-phase3.md สำหรับ system design (§1 Protocol Template system)
3. อ่าน .project/context.md D18 สำหรับเหตุผล
4. อ่าน app/lib/records/storage_repository.dart ก่อน — ทำตาม pattern เดียวกัน (abstract + PathProvider + InMemory)
5. เขียน test ก่อน (TDD) — model serialization, InMemory CRUD, provider state changes
6. ทำเสร็จ commit ด้วยข้อความ: "feat(app): protocol template model + repository + providers (#22)"

หลังเขียน:
1. รัน verification-loop (flutter analyze + flutter test)
2. อัปเดต .project/progress.md ว่า subtask #22 เสร็จแล้ว
