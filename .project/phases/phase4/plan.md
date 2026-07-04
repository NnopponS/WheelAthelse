# WheelAthlete Phase 4 — In-App Session Preview & Quality Indicators

## Objective
เพิ่ม 2 feature หลักให้แอป WheelAthlete: (1) **Session preview/playback** — เปิดดู session ที่บันทึกแล้วได้ในแอป ทั้งจาก Browse (tap session) และหลัง Stop recording (ปุ่ม Preview ใน stopped view). แสดง full IMU chart (accel/gyro per axis, both wheels) แบบ scrub/zoom ได้, summary stats (duration, sample count, drop count, sync quality, mean/peak accel), และ export/share จากหน้า preview ได้เลย. สำหรับ session ใหญ่ (200Hz × 5min = 60k samples) ใช้ lazy load chunks ตามที่ scrub ไป เพื่อกัน memory pressure. (2) **Quality badges ใน Browse** — แสดง sync quality color (เขียว/เหลือง/แดงตาม drift residual RMS) ที่ session list item เพื่อให้ triage session ดี/เสียได้เร็ว.

## Architecture
See `architecture.md`

## Subtasks
- [x] #30: Sample chunk reader + decimation for preview — skill: dart-flutter-patterns + tdd-workflow
- [x] #31: Session stats computation (pure logic) — skill: dart-flutter-patterns + tdd-workflow
- [x] #32: Quality badge color thresholds (pure logic) — skill: dart-flutter-patterns + tdd-workflow
- [x] #33: Session preview page (chart + scrub + stats) — skill: dart-flutter-patterns + tdd-workflow
- [x] #34: Preview entry points (Browse tap + stopped view button) — skill: dart-flutter-patterns + tdd-workflow
- [x] #35: Export/share from preview page — skill: dart-flutter-patterns + tdd-workflow
- [x] #36: Quality badges in Browse session list — skill: dart-flutter-patterns + tdd-workflow

## Progress
See `progress.md`

## Dependency Graph
```
#30 (chunk reader) ─┐
#31 (stats)         ├──→ #33 (preview page) ──→ #34 (entry points) ──→ #35 (export from preview)
#32 (badge color)   ──→ #36 (badges in Browse)

Independent pairs:
- #30, #31, #32 can run in parallel (no deps)
- #36 depends only on #32
- #33 depends on #30 + #31
- #34 depends on #33
- #35 depends on #34
```
