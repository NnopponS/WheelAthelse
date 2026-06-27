---
PROMPT FOR SUBTASK #1: Project scaffolding + monorepo + git/GitHub + BLE protocol spec
---
ใช้ git-workflow skill เพื่อ scaffold โปรเจค WheelSense แบบ monorepo และตั้ง git + GitHub

Context:
- Project: WheelSense (ระบบวิเคราะห์การเคลื่อนไหวนักกีฬาวีลแชร์ด้วย IMU)
- Subtask: #1 of 10
- Stack: monorepo (firmware = PlatformIO/Arduino C++, app = Flutter)
- Depends on: none
- Files to touch: โครงสร้างทั้ง repo, README.md, .gitignore, docs/ble-protocol.md

งานที่ต้องทำ:
1. สร้างโครงสร้าง monorepo:
   - firmware/  (เปล่าๆ ก่อน + README อธิบายว่าจะเป็น PlatformIO project)
   - app/       (เปล่าๆ ก่อน + README)
   - docs/
   - README.md หลัก อธิบายภาพรวมโปรเจค + วิธี build แต่ละส่วน
2. .gitignore ครอบคลุม Flutter, PlatformIO, OS files
3. เขียน docs/ble-protocol.md ให้ละเอียด (contract ระหว่าง firmware กับ app):
   - Service UUID + Characteristic UUIDs (กำหนดค่าจริง เช่น ใช้ 128-bit UUID)
   - IMU binary packet layout: [uint32 seq][uint32 t_device_us][int16 ax..gz], batch หลาย sample/notify
   - Control characteristic: คำสั่ง start/stop/set_rate + **synchronized start (target_start_us)** + **sync_ping**
   - Sync characteristic (Notify/Indicate): echo t_device_us ตอบ sync_ping สำหรับ clock-offset estimation
   - Info characteristic: wheel id (L/R), fw version, scale factor
   - ระบุ data schema CSV + โครงสร้างโฟลเดอร์ topic/trial (อ้างอิง architecture.md หัวข้อ 3-5)
4. git init + commit แรก
5. สร้าง GitHub repo (gh repo create) แบบ private แล้ว push
   - ถ้ายังไม่ login: หยุดถามผู้ใช้ก่อน อย่าเดา credentials

ก่อนเขียนโค้ด:
1. อ่าน .project/plan.md และ .project/architecture.md สำหรับ context เต็ม
2. commit ด้วยข้อความ: "chore: scaffold monorepo and define BLE protocol"

หลังเขียน:
1. อัปเดต .project/progress.md ว่า subtask #1 เสร็จแล้ว (ใส่ commit hash)
2. ยืนยันว่า docs/ble-protocol.md พร้อมให้ทั้ง firmware และ app ใช้อ้างอิง

Done when:
- monorepo มี firmware/, app/, docs/, README.md, .gitignore
- docs/ble-protocol.md สมบูรณ์ (UUID + packet layout + commands)
- push ขึ้น GitHub สำเร็จ (หรือ commit local ถ้าผู้ใช้ยังไม่พร้อม GitHub)
