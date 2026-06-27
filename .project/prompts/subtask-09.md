---
PROMPT FOR SUBTASK #9: Flutter — CSV export (synced/resampled) + folder hierarchy + share
---
ใช้ dart-flutter-patterns skill เพื่อ export ข้อมูลเป็น CSV ในโครงสร้างโฟลเดอร์

Context:
- Project: WheelSense
- Subtask: #9 of 10
- Stack: Flutter, csv, path_provider, share_plus
- Depends on: #8 (recording buffer + folder structure)
- Files to touch: app/lib/export/, app/lib/ui/browse_*.dart, export_*.dart

งานที่ต้องทำ:
1. export session → CSV ตาม schema (architecture.md หัวข้อ 3):
   columns: seq, wheel, timestamp_app_ms, timestamp_device_us, timestamp_synced_ms,
            ax, ay, az, gx, gy, gz, marker
   - ไฟล์รวม เรียงตาม timestamp_synced_ms (คอลัมน์ wheel แยก L/R)
2. **(option) resampling:** เลือกได้ว่าจะ resample/interpolate ทั้ง 2 ล้อเป็น grid เวลาเดียวกัน
   (เช่น ทุก 10ms) เพื่อให้แต่ละแถวมี L/R ที่เวลาเดียวกัน — ดีสำหรับ train model
3. meta.json ต่อ session: session_id, topic, trial, datetime, ผู้ทดสอบ, sample rate,
   sync quality (offset/drift residual), จำนวน sample/marker, ชื่อไฟล์วิดีโอกล้อง (ผู้ใช้กรอก)
4. หน้า browse (ใช้ SessionListItem จาก #4): topic → trial → session
   ดูรายละเอียด / export / share / ลบ
5. share ออกจากเครื่อง (share_plus) — แชร์ทั้งโฟลเดอร์ topic, trial, หรือ session เดียว
6. ข้อมูลใหญ่: เขียนไฟล์แบบ stream (อย่า build string ก้อนเดียวใน memory)

ก่อนเขียนโค้ด:
1. อ่าน architecture.md (หัวข้อ 3 Data format + 5 Storage) ให้คอลัมน์ตรงกับที่ model เฟสหน้าใช้
2. เขียน test ก่อน (TDD): unit test CSV serializer (header/rows/marker/escaping) + resampler
3. commit ด้วยข้อความ: "feat(app): export synced CSV with folder hierarchy, metadata, and sharing"

หลังเขียน:
1. flutter analyze + flutter test ผ่าน
2. ทดสอบเปิด CSV ใน pandas/Excel ว่า parse ได้ + timestamp_synced_ms เรียงถูก
3. อัปเดต .project/progress.md ว่า subtask #9 เสร็จแล้ว

Done when:
- export CSV ถูก schema + meta.json ครบ + อยู่ในโฟลเดอร์ topic/trial
- (option) resampling ใช้งานได้
- หน้า browse + share ทำงาน
- เปิดใน pandas/Excel ได้ถูกต้อง, unit test ผ่าน
