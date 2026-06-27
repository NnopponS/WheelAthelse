---
PROMPT FOR SUBTASK #5: Flutter — scan + เชื่อม 2 devices (L/R) + state management
---
ใช้ dart-flutter-patterns skill เพื่อสร้างระบบเชื่อม BLE 2 ตัว

Context:
- Project: WheelSense
- Subtask: #5 of 10
- Stack: Flutter, flutter_blue_plus, riverpod
- Depends on: #1 (protocol), #4 (design system/component). ทำหลัง firmware ได้แต่ test ด้วย mock ก่อนได้
- Files to touch: app/lib/ble/, app/lib/state/, app/lib/ui/scan_*.dart, connect_*.dart

งานที่ต้องทำ:
1. สร้าง Flutter project ใน app/ (ถ้ายังไม่มี) รองรับ iOS + Android
2. เพิ่ม dependency: flutter_blue_plus, flutter_riverpod, permission_handler
3. ตั้ง permission BLE (Android manifest + iOS Info.plist: bluetooth, location)
4. หน้า Scan: list อุปกรณ์ WheelSense-L / WheelSense-R (ใช้ ConnectionCard จาก #4)
5. เชื่อมพร้อมกัน 2 ตัว, จัดการ connection state แยก L/R (connected/connecting/disconnected/reconnecting)
6. State management ด้วย riverpod: provider เก็บสถานะ 2 connections
7. UI ใช้ component + theme จาก #4 ให้สวยและสม่ำเสมอ
8. auto-reconnect เบื้องต้นเมื่อหลุด

ก่อนเขียนโค้ด:
1. อ่าน architecture.md (ส่วน App) + docs/ble-protocol.md (UUID) + ใช้ widget จาก #4
2. เขียน test ก่อน (TDD): unit test connection state logic (mock BLE)
3. commit ด้วยข้อความ: "feat(app): scan and connect two BLE devices (L/R) with state management"

หลังเขียน:
1. flutter analyze + flutter test ผ่าน
2. อัปเดต .project/progress.md ว่า subtask #5 เสร็จแล้ว

Done when:
- เชื่อม 2 BLE device พร้อมกันได้ (firmware จริงหรือ mock)
- state แยก L/R ถูกต้อง, UI สวยตาม design system
- unit test connection logic ผ่าน
