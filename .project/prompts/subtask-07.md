---
PROMPT FOR SUBTASK #7: Flutter — Clock sync engine (2 ล้อ sync แบบสมบูรณ์)
---
ใช้ dart-flutter-patterns skill เพื่อสร้างระบบ sync เวลา 2 ล้อแบบสมบูรณ์

Context:
- Project: WheelSense
- Subtask: #7 of 10  ← หัวใจของความแม่นยำ ทำให้ L/R sync กันจริง
- Stack: Flutter, riverpod
- Depends on: #3 (firmware รองรับ sync_ping + synchronized start) + #6 (มี packet stream)
- Files to touch: app/lib/sync/, app/lib/state/

ปัญหาที่ต้องแก้:
2 ล้อเป็น M5 คนละตัว นาฬิกา micros() ไม่ตรงกันและ drift, BLE notify มี latency/jitter
ต่างกันแต่ละ connection → app timestamp ดิบไม่แม่นพอ ต้อง map ทุก sample เข้า common timeline

งานที่ต้องทำ:
1. **Offset estimation (NTP/PTP-lite ผ่าน BLE):**
   - ส่ง sync_ping ไปแต่ละ device หลายครั้ง, รับ echo t_device_us กลับ
   - วัด round-trip, เก็บคู่ (t_app_ms, t_device_us) ที่ round-trip ต่ำสุดเพื่อลด noise
   - ประเมิน offset ระหว่าง device clock กับ app clock ต่อ device (L และ R แยกกัน)
2. **Drift correction:**
   - เก็บคู่ (t_device_us, t_app_ms) หลายจุดตลอด session → fit linear (slope = drift rate)
   - ฟังก์ชันแปลง: deviceTimestamp → timestamp_synced_ms บน common timeline
   - ทำ re-estimation เป็นช่วง (เช่น ทุก 10-30 วิ) เพื่อ track drift
3. **Scheduled synchronized start +5s + countdown (common reference = นาฬิกามือถือ):**
   - กดเริ่ม → app กำหนด T_start = now_phone + 5s
   - ใช้ offset/drift (ข้อ 1-2) แปลง T_start เป็น local micros (target_start_us) ของแต่ละ device
   - ส่ง scheduled start ให้ทั้ง 2 device → เริ่มเก็บ ณ instant เดียวกันบน timeline มือถือ
   - แสดง countdown 5..4..3..2..1 ใน UI; firmware จะ beep 3-2-1 จากลำโพง (subtask #3)
   - บันทึก beep T-0 เป็น sync marker (audio marker สำหรับ align กับวิดีโอกล้อง)
4. **คำนวณ timestamp_synced_ms** ให้ทุก ImuSample (เติมเข้า model จาก #6)
5. **Sync quality metric:** residual จาก linear fit + ความต่างเวลา beep/marker ระหว่าง 2 ล้อ
   → แสดงใน UI (เช่น "sync ±2ms") และเก็บลง meta.json (subtask #9)

ก่อนเขียนโค้ด:
1. อ่าน architecture.md (หัวข้อ 4 Time Sync) + docs/ble-protocol.md (sync_ping/Sync char)
2. เขียน test ก่อน (TDD): unit test offset/drift estimator ด้วยข้อมูลจำลอง
   (clock ที่มี offset + drift + noise) → ตรวจว่า synced timeline คลาดเคลื่อนต่ำ
3. commit ด้วยข้อความ: "feat(app): clock sync engine for precise dual-wheel time alignment"

หลังเขียน:
1. flutter analyze + flutter test ผ่าน
2. อัปเดต .project/progress.md ว่า subtask #7 เสร็จแล้ว

Done when:
- offset + drift estimator ทำงาน (unit test ยืนยันความแม่นด้วยข้อมูลจำลอง)
- ทุก sample มี timestamp_synced_ms บน common timeline (นาฬิกามือถือ)
- scheduled start +5s + countdown ทำงาน, 2 ตัวเริ่ม instant เดียวกัน + แสดง sync quality
- beep/marker ของ 2 ล้อ align กัน (ความต่าง < 1 sample interval ในการทดสอบ)
