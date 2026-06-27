---
PROMPT FOR SUBTASK #6: Flutter — parse packet + realtime display
---
ใช้ dart-flutter-patterns skill เพื่อ parse IMU packet และแสดง realtime

Context:
- Project: WheelSense
- Subtask: #6 of 10
- Stack: Flutter, riverpod, fl_chart
- Depends on: #3 (firmware ส่ง notify จริง) + #5 (เชื่อมได้) + #4 (component)
- Files to touch: app/lib/ble/packet_parser.dart, app/lib/ui/realtime_*.dart, app/lib/state/

งานที่ต้องทำ:
1. เขียน parser แปลง binary packet → ImuSample objects
   - layout ตาม docs/ble-protocol.md: [uint32 seq][uint32 t_device_us][int16 ax..gz]
   - รองรับ batch หลาย sample ต่อ notify, little-endian
   - แปลง raw int16 → ค่าจริงด้วย scale factor (g, dps)
2. รับ stream จาก 2 ตัว (L/R) แยกกัน
3. UI realtime (ใช้ LiveMetricTile + theme จาก #4): แสดงค่าปัจจุบัน 6 แกนต่อล้อ
   + กราฟ scroll (fl_chart) สวยอ่านง่าย
4. แสดง effective sample rate จริง (คำนวณจาก seq/timestamp) + ตรวจ packet loss
5. throughput สูง: throttle การ rebuild UI (อย่า setState ทุก packet)

ก่อนเขียนโค้ด:
1. อ่าน docs/ble-protocol.md ให้ parser ตรง layout เป๊ะ
2. เขียน test ก่อน (TDD): unit test packet_parser ด้วย byte array ตัวอย่าง (batch + edge cases)
3. commit ด้วยข้อความ: "feat(app): parse batched IMU packets and show realtime data"

หลังเขียน:
1. flutter analyze + flutter test ผ่าน
2. อัปเดต .project/progress.md ว่า subtask #6 เสร็จแล้ว

Done when:
- parser แปลง packet ถูกต้อง (unit test ครอบคลุม batch + little-endian + scale)
- UI แสดง 6 แกน × 2 ล้อ realtime ลื่น ไม่ค้าง สวยตาม design system
- แสดง effective sample rate + packet loss
