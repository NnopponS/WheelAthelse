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
> [subtask #4] design system + theme + reusable components + showcase พร้อมแล้ว
> หน้า home คือ Showcase (living style guide) — ใช้ `flutter run` ดูได้
> ถัดไป: subtask #5 (BLE scan + connect) จะนำ theme/components เหล่านี้ไปใช้

## โครงสร้าง (ปัจจุบัน + เป้าหมาย)
```
app/
├── lib/
│   ├── main.dart            # ✅ root + theme wiring (home = showcase)
│   ├── theme/               # ✅ design system (subtask #4)
│   │   ├── app_palette.dart      # color primitives
│   │   ├── app_dimens.dart       # spacing / radius / sizing
│   │   ├── app_typography.dart   # Inter + JetBrains Mono (tabular metrics)
│   │   ├── wheelsense_colors.dart# ThemeExtension: L/R + semantic colors
│   │   ├── wheel_side.dart        # WheelSide enum (L/R)
│   │   ├── app_theme.dart        # light/dark ThemeData
│   │   └── theme.dart            # barrel export
│   ├── widgets/             # ✅ reusable components (subtask #4)
│   ├── ui/                  # ✅ showcase / preview page
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
