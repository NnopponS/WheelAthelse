---
PROMPT FOR SUBTASK #2: Firmware — อ่าน IMU MPU6886 ที่ rate ปรับได้ + แสดงบนจอ + serial debug
---
ใช้ cpp-coding-standards skill เพื่อเขียน firmware M5StickCPlus2 อ่าน IMU

Context:
- Project: WheelSense
- Subtask: #2 of 10
- Stack: PlatformIO + Arduino framework (ESP32), M5Unified library
- Hardware: M5StickCPlus2, IMU ในตัว = MPU6886 (accel + gyro 3 แกน)
- Depends on: #1
- Files to touch: firmware/platformio.ini, firmware/src/main.cpp (+ โมดูลย่อย)

งานที่ต้องทำ:
1. ตั้ง PlatformIO project ใน firmware/ สำหรับ M5StickCPlus2 (board: m5stack-stickc, platform espressif32)
2. ใช้ M5Unified / register ของ MPU6886 อ่าน IMU (accel x/y/z, gyro x/y/z)
3. **ใช้ data-ready interrupt + hardware FIFO ของ MPU6886 (สำคัญ — กันข้อมูลหาย):**
   - ตั้ง sample rate ที่ตัว sensor + เปิด FIFO + เปิด data-ready interrupt (INT pin)
   - ISR สั้นที่สุด (set flag / อ่าน FIFO count) → drain FIFO ใน task หลัก
   - ใช้ ring buffer / FreeRTOS queue ส่งต่อ sample (เตรียมให้ #3 มี BLE task แยก core)
   - อย่าใช้ busy polling delay เปล่าๆ ที่ทำให้ interval เพี้ยน
4. อ่านที่ sampling rate ปรับได้ — รองรับ 50/100/200 Hz (เริ่ม default 100 Hz)
   - เก็บ micros() ต่อ sample (อิงเวลาที่ data-ready จริง)
5. แสดงบนจอ M5: wheel id (L/R), sample rate, sample count, battery, FIFO/drop count
6. ส่งค่าออก Serial เป็น CSV เพื่อ debug ก่อน (ยังไม่ทำ BLE ใน subtask นี้)
7. แยกโค้ดอ่าน IMU เป็นโมดูล (เช่น imu_reader.h/.cpp) + queue ให้ subtask #3 เอาไป feed BLE
8. เก็บ scale factor (LSB→g, LSB→dps) ให้สอดคล้องกับ docs/ble-protocol.md

ก่อนเขียนโค้ด:
1. อ่าน .project/architecture.md (ส่วน Firmware) และ docs/ble-protocol.md
2. commit ด้วยข้อความ: "feat(firmware): read MPU6886 IMU at configurable rate with serial output"

หลังเขียน:
1. ถ้าไม่มีบอร์ดจริง: อย่างน้อยให้ build ผ่าน (pio run) เพื่อยืนยัน compile
2. อัปเดต .project/progress.md ว่า subtask #2 เสร็จแล้ว

Done when:
- pio run compile ผ่าน
- อ่าน IMU 6 แกนผ่าน data-ready interrupt + FIFO ที่ rate ปรับได้ + แนบ device timestamp
- มี ring buffer / queue ที่ #3 เอาไปต่อ BLE task แยก core ได้
- module imu_reader พร้อมให้ #3 ใช้
- จอแสดงสถานะ (รวม FIFO/drop count) + Serial ออกค่า CSV ได้
