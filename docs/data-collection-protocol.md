# WheelAthlete — Data Collection Protocol

Current release line: `v1.8.0`.

เอกสารนี้คือขั้นตอนมาตรฐานสำหรับเก็บข้อมูล WheelAthlete ด้วย sensor ล้อซ้าย/ขวา โดยใช้ **operator client เพียงหนึ่งตัวต่อ sensor pair ในเวลาเดียวกัน**:

- Flutter Mobile App (iOS/Android), หรือ
- Python Windows Research Edition

## 1. เตรียมอุปกรณ์

- WheelAthlete sensor 2 ตัว (L/R): M5StickCPlus2 หรือ XIAO nRF52840 Sense ตามชุดที่ทดลอง
- firmware `1.8.0` ที่ตรงกับ target
- โทรศัพท์ iOS/Android **หรือ** Windows PC
- กล้อง gold standard ถ้าต้องการ video alignment
- สายชาร์จ/แหล่งจ่ายไฟและอุปกรณ์ยึด sensor

## 2. ติดตั้ง sensor

1. ติด sensor ซ้าย/ขวาที่ตำแหน่งที่กำหนดไว้อย่างสม่ำเสมอทุก trial
2. ยึดให้แน่น ไม่ขยับระหว่างการทดลอง
3. จด orientation/ตำแหน่งติดตั้งถ้างานวิเคราะห์ต้องใช้ axis convention แบบตายตัว
4. ตรวจ balance ของล้อและความปลอดภัยก่อนเริ่ม

## 3. เตรียมกล้อง (ถ้าใช้)

- ให้เห็นบริเวณการเคลื่อนไหวที่ต้องวิเคราะห์
- แนะนำ 60 fps หรือสูงกว่าเมื่อ motion timing สำคัญ
- เปิด audio ถ้าจะใช้ countdown/beep เป็น alignment event
- เริ่มอัดกล้อง **ก่อน** เริ่ม WheelAthlete recording

## 4. เชื่อมต่อ

เลือก client เดียว:

### Mobile

1. เปิด Flutter Mobile App
2. scan และ connect sensor L/R
3. ตรวจ identity, battery, sampling rate และ health status
4. รอ/สั่ง clock synchronization ให้พร้อมก่อน record

### Windows

1. เปิด `run_python_pc_app.bat` หรือโปรแกรมที่ติดตั้งแล้ว
2. Dashboard → scan/connect sensor L/R
3. ตรวจ device/FW, battery, RSSI/MTU, sampling rate และ diagnostics
4. Sync clocks ก่อน record

> ห้ามเปิด Mobile และ Windows เพื่อควบคุม sensor pair เดียวกันพร้อมกัน

## 5. ตั้งค่าการทดลอง

ก่อนเริ่มแต่ละ trial ให้บันทึกอย่างน้อย:

- athlete / participant identifier
- topic / protocol
- trial number
- sampling rate (50 / 100 / 200 Hz)
- notes/tags ที่จำเป็น
- camera filename ถ้ามี

ค่าที่เลือกต้องถูกส่งไป configure sensor จริง ไม่ใช่เปลี่ยนเฉพาะ metadata

## 6. Start recording

1. ถ้าใช้กล้อง ให้เริ่ม camera recording ก่อน
2. กด Start ใน WheelAthlete client
3. รอ synchronized countdown/start lifecycle ให้เสร็จ
4. ตรวจว่า sensor ที่คาดหวังทั้งหมด acknowledge START และเริ่มมี sample
5. ถ้า client แจ้ง fatal acquisition/storage error ให้หยุด trial และแก้ปัญหาก่อนเก็บใหม่

Mark Event ไม่อยู่ใน recording UI ปัจจุบัน การ align video ใช้ countdown/beep และ lifecycle/timestamp evidence ใน post-processing ตาม workflow ของงานวิจัย

## 7. ระหว่างเก็บข้อมูล

ให้ดูตัวชี้วัด integrity มากกว่า RSSI เพียงอย่างเดียว:

- effective sample rate
- sequence gaps / duplicates / out-of-order
- queue drops / queue depth
- transport failures
- FIFO/sample-loss telemetry เมื่อ firmware รองรับ
- synchronization RTT / drift / residual

RSSI ใช้เป็น RF context เท่านั้น ไม่ใช่หลักฐานว่าข้อมูลครบ

## 8. Stop recording

1. กด Stop ที่ WheelAthlete client
2. รอ STOP acknowledgement / finalization ให้ครบ
3. ตรวจ final QC ก่อนถือว่า trial ใช้งานได้
4. ถ้าใช้กล้อง ค่อยหยุดกล้องหลัง WheelAthlete stop เสร็จ

## 9. ตรวจและ export

### Mobile

- เปิด session preview
- ตรวจ quality/statistics
- export CSV / Excel / ZIP ตามงานที่ต้องใช้
- share/save ผ่านระบบปฏิบัติการ

### Windows

- เก็บ finalized `.waj` เป็น authoritative research record
- ตรวจ final QC ใน Sessions/Diagnostics
- export CSV เป็น derived artifact เมื่อต้องใช้วิเคราะห์
- หากเกิด crash และมี `.open` journal ให้ใช้ recovery workflow ก่อนทิ้งข้อมูล

## 10. ก่อนนำข้อมูลไปวิเคราะห์

ตรวจอย่างน้อย:

- sensor L/R มีข้อมูลครบตามที่คาดหวัง
- ไม่มี unresolved fatal loss/QC condition
- sampling rate และ duration สมเหตุสมผล
- metadata / athlete / topic / trial ถูกต้อง
- timestamp/synchronization provenance ชัดเจน
- video filename และ alignment evidence ถูกบันทึกถ้าใช้กล้อง

## 11. Physical acceptance

Automated test/demo/simulation ไม่สามารถยืนยัน RF จริงหรือ physical start skew ได้ การกล่าวอ้างเรื่องระยะ 0.5/2/5 m, throughput/loss จริง หรือ L/R start skew ต้องมาจาก physical acceptance matrix ที่อยู่ใน `docs/testing/pc-version-phase-10-acceptance-plan.md`
