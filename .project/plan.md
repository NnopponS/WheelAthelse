# WheelAthlete — Phase 1: Data Collection & Calibration

## Objective
สร้างระบบเก็บข้อมูลดิบ (raw data) สำหรับงานวิจัยวิเคราะห์การเคลื่อนไหวนักกีฬาวีลแชร์
ด้วย IMU sensor ที่ติดล้อ แทนการใช้ 3D Motion Capture หลายกล้อง ประกอบด้วย
(1) Firmware บน M5StickCPlus2 จำนวน 2 ตัว (ล้อซ้าย-ขวา) อ่าน IMU ในตัว (MPU6886)
accel+gyro 3 แกน ที่ sampling rate ปรับได้ ส่งออกผ่าน BLE และ
(2) Flutter mobile app (iOS+Android) เชื่อม BLE พร้อมกัน 2 ตัว แสดงสถานะ realtime
บันทึก raw data พร้อม timestamp แม่นยำ มีปุ่ม Mark Event เพื่อ sync กับกล้อง
(gold standard ถ่ายแยก align ทีหลัง) และ export เป็น CSV เพื่อนำไป train model เฟสถัดไป

## Architecture
ดู `.project/architecture.md`

## Tech stack
- Firmware: PlatformIO + Arduino C++ (ESP32), M5Unified, NimBLE-Arduino
- App: Flutter / Dart, flutter_blue_plus, riverpod, fl_chart, csv, share_plus, path_provider
- App UI: design system ของตัวเอง (skill: impeccable + ui-ux-pro-max)
- Repo: Monorepo (firmware/ + app/)
- Export: CSV (synced timeline) จัดเก็บเป็นโฟลเดอร์ topic/trial

## Subtasks
- [ ] #1: Scaffolding + monorepo + git/GitHub + BLE protocol spec (incl. sync + folder model) — skill: `git-workflow` — status: pending
- [ ] #2: Firmware — อ่าน IMU MPU6886 ที่ rate ปรับได้ + แสดงบนจอ + serial debug — skill: `cpp-coding-standards` — status: pending
- [ ] #3: Firmware — BLE GATT + time-sync support (notify/control/sync/info, synchronized start) — skill: `cpp-coding-standards` — status: pending
- [ ] #4: Flutter — design system / theme / reusable components (UI สวย) — skill: `impeccable` + `ui-ux-pro-max` — status: pending
- [ ] #5: Flutter — scan + เชื่อม 2 devices (L/R) + state management — skill: `dart-flutter-patterns` — status: pending
- [ ] #6: Flutter — parse packet + realtime display (ใช้ design system) — skill: `dart-flutter-patterns` — status: pending
- [ ] #7: Flutter — Clock sync engine (offset/drift, synchronized start, common timeline) — skill: `dart-flutter-patterns` — status: pending
- [ ] #8: Flutter — recording session + Mark Event + จัดเก็บโฟลเดอร์ topic/trial — skill: `dart-flutter-patterns` — status: pending
- [ ] #9: Flutter — CSV export (synced/resampled) + folder hierarchy + meta.json + share — skill: `dart-flutter-patterns` — status: pending
- [ ] #10: เอกสาร data-collection protocol + field test (verify sync + กล้อง) — skill: `tdd-workflow` — status: pending

## Dependency graph
```
#1 (scaffold + BLE/sync/folder protocol spec)
 ├──► #2 (firmware IMU) ──► #3 (firmware BLE + sync) ──┐
 ├──► #4 (design system) ──┐                          │
 └──────────────────────┐  │                          │
                        ▼  ▼                          │
                  #5 (flutter connect 2 devices) ◄─────┘
                        │
                  #6 (parse + realtime display)
                        │
                  #7 (clock sync engine) ◄── ต้องการ #3 (sync support)
                        │
                  #8 (recording + mark + folder)
                        │
                  #9 (CSV export synced + folders)
                        │
                  #10 (field protocol + verify sync)
```
- #2 (firmware) และ #4 (design system) ทำขนานกันได้หลัง #1 เสร็จ
- #5 ใช้ component จาก #4; #6 ต้องรอ #3 (firmware ส่งจริง) + #5 (เชื่อมได้)
- #7 (sync engine) เป็นหัวใจของความแม่นยำ — ต้องการ firmware sync support (#3)

## Progress
ดู `.project/progress.md`

## How to continue (ข้าม session)
1. เปิด session ใหม่ พิมพ์ `/navigator` หรือ `ใช้ build skill: ทำ subtask #N จาก .project/plan.md`
2. build skill จะอ่าน plan.md + architecture.md + progress.md ก่อนเริ่ม
3. ทำทีละ subtask, เขียน test ก่อน, commit, แล้วอัปเดต progress.md
