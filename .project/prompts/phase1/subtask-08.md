---
PROMPT FOR SUBTASK #8: Flutter — recording session + Mark Event + จัดเก็บโฟลเดอร์ topic/trial
---
ใช้ dart-flutter-patterns skill เพื่อทำระบบบันทึก session + จัดโฟลเดอร์

Context:
- Project: WheelAthlete
- Subtask: #8 of 10
- Stack: Flutter, riverpod, path_provider
- Depends on: #6 (stream) + #7 (synced timestamp)
- Files to touch: app/lib/recording/, app/lib/storage/, app/lib/state/, app/lib/ui/record_*.dart

งานที่ต้องทำ:
1. **จัดเก็บแบบโฟลเดอร์ topic + trial (ตาม architecture.md หัวข้อ 5):**
   - ก่อนเริ่ม recording: ผู้ใช้เลือก topic เดิม หรือสร้างใหม่ (กรอกชื่อเรื่อง + คำอธิบาย)
   - trial number เพิ่มอัตโนมัติต่อ topic (trial_01, trial_02, ...) — override ได้
   - โครงสร้าง: WheelAthleteData/<topic>/trial_<NN>/  (+ topic_meta.json ระดับ topic)
2. ระบบ recording session: synchronized start/stop ทั้ง 2 ล้อ (เรียกใช้ sync engine #7)
3. แต่ละ sample เก็บ: seq, wheel, timestamp_app_ms, timestamp_device_us,
   timestamp_synced_ms, ax,ay,az,gx,gy,gz, marker
4. ปุ่ม "Mark Event": ใส่ marker=1 ใน sample ที่ตรงเวลา synced ที่สุดของทั้ง 2 ล้อ
   (ใช้ sync กับวิดีโอ: กดพร้อมเคาะล้อให้เห็น spike)
5. UI ขณะ recording (ใช้ component/theme จาก #4): topic+trial ปัจจุบัน, เวลาที่ผ่าน,
   sample count ต่อล้อ, จำนวน marker, sync quality, สถานะ buffer
6. buffer efficient (กัน OOM — flush เป็นช่วงถ้าจำเป็น)
7. edge case: ล้อหลุดกลางทาง → mark gap, ไม่ทำทั้ง session พัง

ก่อนเขียนโค้ด:
1. อ่าน architecture.md (หัวข้อ 3 Data format + หัวข้อ 5 Storage)
2. เขียน test ก่อน (TDD): unit test recording buffer + mark event + trial auto-increment + folder path builder
3. commit ด้วยข้อความ: "feat(app): record sessions into topic/trial folders with synced marks"

หลังเขียน:
1. flutter analyze + flutter test ผ่าน
2. อัปเดต .project/progress.md ว่า subtask #8 เสร็จแล้ว

Done when:
- เลือก/สร้าง topic + auto trial number ได้ → บันทึกลงโฟลเดอร์ถูกโครงสร้าง
- synchronized start/stop 2 ล้อ, Mark Event ใส่ marker ตรงจุดทั้ง 2 ล้อ
- buffer เก็บครบทุก field (รวม timestamp_synced_ms)
- unit test ผ่าน
