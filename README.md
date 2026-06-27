# WheelAthlete

ระบบเก็บข้อมูลดิบเพื่อวิเคราะห์การเคลื่อนไหวนักกีฬาวีลแชร์ด้วย IMU sensor
ที่ติดล้อ (ล้อซ้าย + ล้อขวา) แทนการใช้ 3D Motion Capture หลายกล้อง

## ภาพรวม
- **Firmware** (`firmware/`): บน M5StickCPlus2 จำนวน 2 ตัว อ่าน IMU MPU6886
  (accel + gyro 3 แกน) ที่ sampling rate ปรับได้ ส่งออกผ่าน BLE
- **Mobile App** (`app/`): Flutter (iOS + Android) เชื่อม BLE พร้อมกัน 2 ตัว
  แสดงสถานะ realtime บันทึก raw data พร้อม timestamp แม่นยำ มีปุ่ม Mark Event
  เพื่อ sync กับกล้อง (gold standard) และ export เป็น CSV
- **Docs** (`docs/`): BLE protocol, data-collection protocol

## สถาปัตยกรรม
ดู `.project/architecture.md` และ `docs/ble-protocol.md`

## วิธี build แต่ละส่วน

### Firmware (M5StickCPlus2)
ติดตั้ง [PlatformIO](https://platformio.org/) แล้ว:
```bash
cd firmware
pio run -e left    # build สำหรับล้อซ้าย
pio run -e right   # build สำหรับล้อขวา
pio run -e left -t upload    # flash ลง M5 ตัวซ้าย
```
> รายละเอียดอยู่ใน `firmware/README.md` (subtask #2/#3 จะเพิ่ม code จริง)

### Mobile App (Flutter)
ติดตั้ง [Flutter](https://flutter.dev/) แล้ว:
```bash
cd app
flutter pub get
flutter run -d <device-id>
```
> รายละเอียดอยู่ใน `app/README.md` (subtask #4 เป็นต้นไปจะเพิ่ม code จริง)

## Repo layout
```
WheelAthelse/
├── firmware/      # PlatformIO project (M5StickCPlus2)
├── app/           # Flutter project (iOS + Android)
├── docs/          # BLE protocol + field protocol
├── .project/      # plan / progress / architecture (cross-session context)
└── README.md
```

## Status
Phase 1: Data Collection & Calibration — ดูความคืบหน้าใน `.project/progress.md`
