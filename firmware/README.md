# Firmware — WheelSense (M5StickCPlus2)

Firmware สำหรับ M5StickCPlus2 (ESP32) ที่ติดบนล้อวีลแชร์ (ซ้าย/ขวา)
อ่าน IMU MPU6886 และส่งผ่าน BLE ไปยัง mobile app

## Stack
- **Platform:** PlatformIO + Arduino framework (ESP32)
- **Libraries:** `M5Unified` (IMU + จอ), `NimBLE-Arduino` (BLE ประหยัด RAM)
- **Hardware:** M5StickCPlus2 (MPU6886 IMU ในตัว)

## สถานะปัจจุบัน
> [subtask #1] โฟลเดอร์นี้เป็น scaffold ว่าง — code จริงจะถูกเพิ่มใน subtask #2 (IMU read)
> และ subtask #3 (BLE GATT + time-sync support)

## โครงสร้างเป้าหมาย (หลัง subtask #2/#3)
```
firmware/
├── platformio.ini       # env: left, right (build flag WHEEL_ID=L/R)
├── src/
│   ├── main.cpp
│   ├── imu.cpp          # MPU6886 read + FIFO + ISR
│   ├── ble.cpp          # GATT server + characteristics
│   └── sync.cpp         # clock sync + scheduled start
└── README.md
```

## Build (เมื่อ code พร้อม)
```bash
pio run -e left          # build ล้อซ้าย
pio run -e right         # build ล้อขวา
pio run -e left -t upload    # flash ลง M5 ตัวซ้าย
pio device monitor       # ดู serial debug
```

## BLE Protocol
ดู `../docs/ble-protocol.md` สำหรับ contract เต็ม (UUID, packet layout, control commands)
