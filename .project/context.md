# Decisions Log (ADR-lite)

บันทึกการตัดสินใจตอน grilling — ใช้ทบทวนเหตุผลในอนาคต

## D1: App = Flutter mobile (iOS+Android)
- เลือก Flutter เพราะ BLE stream ข้อมูลความถี่สูงทำได้ดี, UI เร็ว, cross-platform
- ทางเลือกที่ไม่เลือก: React Native (bridge overhead), Desktop, Web, SD card

## D2: การเชื่อมต่อ = BLE
- เหตุผล: กินไฟน้อย เหมาะใช้ในสนาม, throughput พอสำหรับ IMU raw data
- ข้อควรระวัง: ต้อง batch หลาย sample ต่อ 1 notify เพื่อลด overhead

## D3: เก็บ 2 sensor พร้อมกัน (ล้อซ้าย + ขวา)
- ต้องจัดการ 2 BLE connections พร้อมกัน
- ต้อง sync เวลาระหว่าง 2 ตัว → ใช้ app timestamp (epoch ms) เป็นแกนหลัก

## D4: กล้อง = gold standard ถ่ายแยก, sync ทีหลัง
- app ไม่คุมกล้อง แค่บันทึก IMU + timestamp
- sync ด้วย Mark Event: กดปุ่มใน app พร้อมเคาะล้อแรงๆ ให้เห็น spike ใน accel
  และเห็นการเคาะในวิดีโอ → align ด้วยเหตุการณ์ร่วม

## D5: IMU = ตัวในตัว M5StickCPlus2 (MPU6886)
- ไม่ต่อ IMU ภายนอก
- ต้องบันทึก scale factor (LSB→g, LSB→dps) ไว้แปลงค่า

## D6: ขอบเขต = firmware + app ทั้งคู่
- firmware: PlatformIO + Arduino C++
- app: Flutter

## D7: Sampling rate = ปรับได้ (configurable)
- รองรับ 50/100/200 Hz ตั้งผ่าน app → ส่ง config ไป firmware
- ค่า default แนะนำ 100 Hz (มาตรฐานวิเคราะห์การเคลื่อนไหว)

## D8: Export = CSV
- คอลัมน์: timestamp_app_ms, timestamp_device_us, wheel, ax, ay, az, gx, gy, gz, marker
- + meta.json ต่อ session

## D9: Repo = Monorepo
- firmware/ และ app/ อยู่ใน repo เดียว จัดการง่ายตอนเริ่ม

## D10: UI ต้องสวย → มี design system
- ทำ design system/theme เป็น subtask แยก (#4) ก่อนสร้างหน้าจอ → ทุกหน้าจอสม่ำเสมอ
- contrast สูงสำหรับใช้กลางแดดในสนาม, L/R สีต่างชัดเจน
- skill: impeccable + ui-ux-pro-max
- ปุ่มหลักใหญ่ กดง่ายตอนเคลื่อนไหว, มี empty/loading/error state ครบ

## D11: บันทึกแบบจัดโฟลเดอร์ topic + trial
- โครงสร้าง: WheelAthleteData/<topic>/trial_<NN>/session_<id>.csv (+ meta.json)
- ผู้ใช้เลือก/สร้าง topic (เรื่องที่เก็บ) ก่อนเริ่ม, trial เพิ่มอัตโนมัติต่อ topic
- มีหน้า browse: topic → trial → session

## D12: Sync 2 ล้อแบบสมบูรณ์ (clock-offset estimation)
- ไม่พึ่ง app timestamp ดิบ (BLE jitter) → ทำ clock sync engine เป็น subtask แยก (#7)
- offset estimation ผ่าน sync_ping (NTP/PTP-lite) + drift correction (linear fit)
- synchronized start ทั้ง 2 device + คอลัมน์ timestamp_synced_ms เป็นแกนหลัก
- (option) resample 2 ล้อเป็น grid เวลาเดียวกันตอน export
- firmware (#3) ต้องรองรับ sync_ping echo + synchronized start

## D13: Firmware ใช้ data-ready interrupt + FIFO + dual-core (กันข้อมูลหาย)
- ใช้ hardware FIFO + data-ready interrupt ของ MPU6886 (ไม่ใช่ polling เปล่า)
- ESP32 2 core: acquisition (อ่าน IMU/FIFO) แยกจาก BLE transmission ด้วย FreeRTOS task + queue
- BLE สะดุดต้องไม่ทำ sampling เพี้ยน/ข้อมูลหาย; queue เต็ม → นับ drop count ใส่ meta
- กระทบ subtask #2 (acquisition) และ #3 (BLE task)

## D14: Common reference = นาฬิกามือถือ (ไม่ใช้ UTC จริง)
- ไม่ต้องมี NTP/internet/RTC module
- มือถือเป็น reference กลาง, map device micros → phone timeline ด้วย offset/drift

## D15: Scheduled synchronized start +5s + beep 3-2-1 (beep = audio sync marker)
- กดเริ่ม → app กำหนด T_start = now_phone + 5s → แปลงเป็น local micros ของแต่ละ device
  → ส่ง scheduled start → 2 ตัวเริ่ม ณ instant เดียวกันบน timeline มือถือ
- ระหว่างนับถอยหลัง: ลำโพง M5 ทั้ง 2 ตัว beep 3-2-1 พร้อมกัน
- beep ถูกอัดในวิดีโอกล้อง + เป็น event เวลาแน่นอนใน IMU → ใช้ align วิดีโอ↔IMU (ไม่ต้องเคาะล้อก็ได้)
- กระทบ subtask #3 (firmware beep + scheduled start) และ #7 (app schedule + countdown)
