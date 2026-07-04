---
PROMPT FOR SUBTASK #10: เอกสาร data-collection protocol + field test (verify sync + กล้อง)
---
ใช้ tdd-workflow skill เพื่อเขียนเอกสารขั้นตอนเก็บข้อมูล + ทดสอบจริง

Context:
- Project: WheelAthlete
- Subtask: #10 of 10  (ปิด Phase 1)
- Stack: เอกสาร (Markdown) + field test ของจริง + สคริปต์ Python ตรวจสอบ
- Depends on: #2-#9 (ระบบครบ)
- Files to touch: docs/data-collection-protocol.md, tools/check_session.py

งานที่ต้องทำ:
1. เขียน docs/data-collection-protocol.md ขั้นตอนเก็บข้อมูลในสนามให้ทำซ้ำได้:
   - การติด M5StickCPlus2 บนล้อ (ตำแหน่ง, ทิศ axis, การยึด, ระวัง balance)
   - การตั้งกล้อง gold standard (มุม, ระยะ, fps, แสง)
   - ขั้นตอน sync: เลือก topic/trial → เชื่อม 2 ล้อ → รอ sync quality นิ่ง → เริ่มอัดวิดีโอกล้อง →
     กด start (นับถอยหลัง 5 วิ, beep 3-2-1 จากลำโพง 2 ตัว = audio sync marker ที่อยู่ในวิดีโอด้วย) →
     เก็บข้อมูล → กด Mark Event เพิ่มได้ระหว่างทาง → จบด้วยอีก beep/มาร์ก
   - หมายเหตุ: เสียง beep ในวิดีโอใช้ align กับ marker ใน IMU ได้โดยตรง (ไม่ต้องเคาะล้อ
     แต่เคาะล้อเพิ่มเป็น cross-check ได้)
   - checklist ก่อนแต่ละ trial (แบต, เชื่อมครบ 2 ล้อ, sample rate, sync quality, พื้นที่)
   - การตั้งชื่อไฟล์วิดีโอให้ตรงกับ topic/trial/session_id
2. field test จริง 1-2 รอบ: เก็บ → export → ตรวจสอบ
3. สคริปต์ tools/check_session.py ตรวจ CSV:
   - plot accel/gyro 2 ล้อบน timestamp_synced_ms (ดูว่า align กัน)
   - หา marker/beep, วัดความต่างเวลา marker ระหว่าง L/R (verify sync แบบสมบูรณ์)
   - (option) เทียบ beep ในไฟล์เสียงวิดีโอกับ marker ใน IMU เพื่อยืนยัน align กล้อง↔IMU
   - เช็ค effective sample rate จริง + gap/packet loss/drop count
4. บันทึกปัญหา + วิธีแก้ ลง .project/lessons.md (สร้างถ้ายังไม่มี)

ก่อนเริ่ม:
1. อ่าน architecture.md ทั้งหมด ให้ protocol สอดคล้องระบบจริง (โดยเฉพาะ Time Sync + Storage)
2. commit ด้วยข้อความ: "docs: add data-collection protocol and field test with sync validation"

หลังเสร็จ:
1. อัปเดต .project/progress.md → Phase 1 complete
2. บันทึก mempalace ว่าพร้อมเข้า Phase 2 (train model)

Done when:
- docs/data-collection-protocol.md ทำซ้ำได้จริง
- field test ผ่าน: CSV (synced) + วิดีโอ align ได้ด้วย marker
- check_session.py ยืนยันว่า 2 ล้อ sync กัน (marker diff เล็ก) + sample rate ถูก
- บันทึก lessons เรียบร้อย
