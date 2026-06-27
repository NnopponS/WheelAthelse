# Mobile App — WheelSense (Flutter)

Flutter app สำหรับ iOS + Android เชื่อม BLE กับ M5StickCPlus2 ทั้ง 2 ตัว
(ล้อซ้าย + ล้อขวา) แสดงค่า IMU realtime บันทึก session และ export CSV

## Stack
- **Framework:** Flutter / Dart
- **BLE:** `flutter_blue_plus`
- **State:** `riverpod`
- **Chart:** `fl_chart`
- **Storage/Export:** `csv`, `path_provider`, `share_plus`
- **UI:** design system เป็นของตัวเอง (skill: `impeccable` + `ui-ux-pro-max`)

## สถานะปัจจุบัน
> [subtask #1] โฟลเดอร์นี้เป็น scaffold ว่าง — code จริงจะถูกเพิ่มเริ่มจาก subtask #4
> (design system) และ subtask #5 (BLE scan + connect)

## โครงสร้างเป้าหมาย (หลัง subtask #4–#9)
```
app/
├── lib/
│   ├── main.dart
│   ├── theme/               # design system (subtask #4)
│   ├── components/          # reusable UI components
│   ├── ble/                 # BLE manager + packet parser (#5, #6)
│   ├── sync/                # clock sync engine (#7)
│   ├── recording/           # session recorder + mark event (#8)
│   └── export/              # CSV export + share (#9)
├── test/                    # unit + widget tests
└── pubspec.yaml
```

## Build (เมื่อ code พร้อม)
```bash
flutter pub get
flutter run -d <device-id>
flutter test
flutter build apk      # Android
flutter build ios      # iOS (ต้องมี macOS + Xcode)
```

## BLE Protocol
ดู `../docs/ble-protocol.md` สำหรับ contract เต็ม (UUID, packet layout, control commands)
