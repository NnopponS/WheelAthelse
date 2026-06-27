---
PROMPT FOR SUBTASK #3: Firmware — BLE GATT + time-sync support
---
ใช้ cpp-coding-standards skill เพื่อเพิ่ม BLE GATT + การรองรับ time-sync ใน firmware

Context:
- Project: WheelSense
- Subtask: #3 of 10
- Stack: PlatformIO + Arduino C++ (ESP32), NimBLE-Arduino
- Depends on: #2 (มี imu_reader แล้ว)
- Files to touch: firmware/src/ble_service.h/.cpp, firmware/src/main.cpp, platformio.ini

งานที่ต้องทำ:
1. เพิ่ม NimBLE-Arduino เป็น dependency
2. สร้าง BLE GATT server ตาม docs/ble-protocol.md:
   - IMU Data characteristic (Notify): แพ็ค IMU sample เป็น binary packet
     [uint32 seq][uint32 t_device_us][int16 ax][int16 ay][int16 az][int16 gx][int16 gy][int16 gz]
     batch หลาย sample ต่อ 1 notify (เช่น 5-10) เพื่อลด overhead
   - Control characteristic (Write): รับ start/stop/set_rate(Hz) + synchronized start
   - Sync characteristic (Notify/Indicate): ตอบ sync_ping ด้วย t_device_us ปัจจุบันทันที (latency ต่ำสุด)
   - Info characteristic (Read): wheel id (L/R), fw version, scale factor
3. **Time-sync support (สำคัญ):**
   - เมื่อรับ sync_ping ผ่าน Control → ตอบกลับ t_device_us (micros) ทันทีผ่าน Sync characteristic
     ให้ path สั้นที่สุด (ตอบใน callback) เพื่อให้ app ประเมิน clock offset ได้แม่น
   - **Scheduled synchronized start:** รับ target_start_us (เวลาบน local clock ที่ app คำนวณให้)
     → ตั้งเวลาเริ่มเก็บ/ส่งข้อมูล ณ instant นั้นพอดี (ไม่ใช่เริ่มทันทีที่รับคำสั่ง)
4. **Countdown beep 3-2-1 จากลำโพง M5 (= audio sync marker):**
   - ก่อนถึง target_start_us ให้ beep ที่ T-3s, T-2s, T-1s และ beep ยาว/ต่างโทนที่ T-0 (เริ่มจริง)
   - beep ต้องตรงเวลา (อิง target_start_us) เพราะใช้เป็น marker align กับวิดีโอกล้อง
   - ใส่ event/flag ในข้อมูลตอน beep T-0 ด้วย เพื่อให้รู้ตำแหน่ง marker ใน IMU log
5. ตั้งชื่อ BLE advertising แยก L/R ("WheelSense-L", "WheelSense-R")
6. **BLE task แยก core:** ดึง sample จาก queue ของ #2 (FreeRTOS) → batch → notify บนอีก core
   เพื่อไม่ให้ BLE สะดุดกระทบ acquisition
7. แสดงสถานะ BLE บนจอ (advertising / connected / countdown / recording)
8. ทดสอบด้วย nRF Connect: notify ออกจริง + sync_ping ตอบกลับเร็ว + scheduled start ตรงเวลา

ก่อนเขียนโค้ด:
1. อ่าน docs/ble-protocol.md + architecture.md (หัวข้อ Time Sync) ให้ตรงกับที่ app จะใช้
2. commit ด้วยข้อความ: "feat(firmware): add BLE GATT with IMU streaming and time-sync support"

หลังเขียน:
1. pio run ผ่าน
2. อัปเดต .project/progress.md ว่า subtask #3 เสร็จแล้ว

Done when:
- pio run ผ่าน
- BLE advertise แยก L/R, มี characteristics ครบ (IMU/Control/Sync/Info)
- notify ส่ง batched IMU packet ตาม protocol (BLE task แยก core จาก acquisition)
- sync_ping ตอบ t_device_us เร็ว + scheduled start เริ่มตรง target_start_us
- beep 3-2-1 + beep เริ่มจริง ตรงเวลา ใช้เป็น audio sync marker ได้
