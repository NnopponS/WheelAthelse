# WheelAthlete

**ระบบเก็บข้อมูล IMU จากล้อวีลแชร์สองข้างสำหรับงานวิจัยกีฬาวีลแชร์** รองรับการเก็บ accelerometer + gyroscope แบบ synchronized และมีแอปสำหรับใช้งานจริง 2 แบบเท่านั้น: Flutter บนมือถือ และ Python บน Windows

> **Release ปัจจุบัน:** `v1.8.0`
> **Mobile:** `1.8.0+9` · **Firmware:** `1.8.0` · **BLE:** `1.8.0` · **Windows:** `1.8.0`
> **ภาษา:** [English](README.md) · [ภาษาไทย](README.th.md)

## แอปที่รองรับจริง

| แอป | Platform | เทคโนโลยี | ผู้จัดการ BLE | ข้อมูลหลัก |
|---|---|---|---|---|
| Mobile App | iOS + Android | Flutter / Dart | แอปเชื่อม BLE โดยตรง | session CSV + metadata |
| Windows App | Windows 10/11 | Python / PySide6 | acquisition daemon | `.waj` journal + CSV ที่ export |

ตอนนี้ **ไม่มี** Flutter Windows, Flutter Web และ GUI เก่าแบบ Tkinter/Matplotlib ใน source tree แล้ว

## ภาพรวมระบบ

ทั้ง Mobile และ Windows ใช้ BLE protocol เดียวกัน แต่ควรใช้ **client เดียวต่อ sensor pair ในเวลาเดียวกัน**

```text
 Sensor ล้อซ้าย                         Sensor ล้อขวา
 M5StickCPlus2 / XIAO                  M5StickCPlus2 / XIAO
          │                                      │
          └────────────── BLE GATT ──────────────┘
                           │
              ┌────────────┴────────────┐
              │                         │
              ▼                         ▼
      Flutter Mobile App        Python Windows App
        iOS / Android              PySide6 GUI
        เชื่อม BLE ตรง                  │
              │                    localhost IPC
              │                         │
              │                 Acquisition daemon
              │                  Bleak / WinRT BLE
              ▼                         ▼
       CSV + metadata          .waj journal (ข้อมูลหลัก)
       preview + export        QC + recovery + CSV export
```

### Firmware

มี firmware ที่ดูแลจริง 2 target และใช้ protocol เดียวกัน:

- `M5plus2_firmware/` — M5StickCPlus2 / ESP32
- `Xiao_firmware/` — Seeed XIAO nRF52840 Sense

รองรับ L/R, 50/100/200 Hz, synchronized start/stop, range configuration, battery, sequence/loss telemetry, replay/recovery และ acquisition-health diagnostics

### Flutter Mobile App

อยู่ที่ `app/` และรองรับ **iOS + Android เท่านั้น**

ฟีเจอร์หลัก:

- เชื่อม sensor ซ้าย/ขวาพร้อมกันผ่าน BLE
- แสดง Accel XYZ + Gyro XYZ realtime
- clock sync + synchronized recording
- จัด session เป็น topic / trial / session
- protocol template, experiment tracking, tags, search/filter
- session preview, quality/QC, statistics
- export CSV / Excel / ZIP และ share ผ่านระบบปฏิบัติการ

### Python Windows App

อยู่ที่ `tools/pc_gui/` และ `tools/pc_acquisition/`

ตัว GUI ใช้ PySide6 แต่ **ไม่ได้เป็นเจ้าของ raw-data path** ตัว acquisition daemon เป็นคนจัดการ BLE, packet parsing, sequence/loss, clock sync, เขียน `.waj`, final QC และ recovery ส่วน GUI รับเฉพาะ control/status/diagnostics และ preview ที่ลดอัตราแล้วผ่าน localhost IPC

ดังนั้นกราฟช้า หรือ GUI restart จะไม่กลายเป็นสาเหตุที่ทำให้ raw data path หายแบบเงียบ ๆ

## โครงสร้าง repository

```text
WheelAthelse/
├── app/                         # Flutter mobile — iOS + Android
├── M5plus2_firmware/            # M5StickCPlus2 firmware
├── Xiao_firmware/               # XIAO nRF52840 Sense firmware
├── tools/
│   ├── pc_acquisition/          # Windows BLE/recording daemon
│   └── pc_gui/                  # PySide6 Windows UI
├── packaging/
│   └── windows/                 # ไฟล์สร้าง EXE + Installer
├── docs/                        # BLE spec, field protocol, testing, wiki
├── assets/                      # icon/logo
├── .project/                    # สถานะโปรเจกต์ปัจจุบันแบบ canonical
├── run_python_pc_app.bat        # เปิด Windows app จาก source
├── VERSION                      # semantic product version
├── README.md
└── README.th.md
```

## ใช้งาน Windows App จาก source

จาก root ของ repo:

```bat
run_python_pc_app.bat
```

ตัว launcher จะตรวจ dependency และเปิด Python PC App โดย daemon จะถูกเปิดหรือ reuse ให้อัตโนมัติ

ลอง UI โดยไม่ใช้บอร์ดจริง:

```bat
run_python_pc_app.bat --demo
```

Demo จะมีป้าย `DEMO DATA` ชัดเจน และไม่เขียน synthetic data เป็น research evidence

ตำแหน่งข้อมูล default บน Windows:

- Sessions: `~/Documents/WheelAthlete/PC Sessions`
- Log: `~/Documents/WheelAthlete/Logs/python-pc-app.log`
- Experiment presets: `~/Documents/WheelAthlete/experiments.json`

## สร้าง Windows EXE + Installer

ต้องมี Python, PyInstaller และ Inno Setup 6

```bat
packaging\windows\build_installer.bat
```

ไฟล์ output อยู่ใน `release/` ซึ่งถูก ignore จาก Git:

```text
release/WheelAthlete-1.8.0-portable.zip
release/WheelAthleteSetup-1.8.0.exe
```

ทั้ง portable และ installer จะ bundle `WheelAthleteDaemon.exe` มาให้แล้ว ดูรายละเอียดที่ [`packaging/windows/README.md`](packaging/windows/README.md)

## Build Flutter Mobile

```bash
cd app
flutter pub get
flutter run -d <device-id>
flutter test
flutter analyze

flutter build apk --release
flutter build appbundle --release
# iOS ต้องใช้ macOS + Xcode
flutter build ios --release
```

Mobile version ปัจจุบันคือ `1.8.0+9`

## Build / Flash Firmware

### M5StickCPlus2

```bash
cd M5plus2_firmware
pio run -e left
pio run -e right
pio run -e left -t upload
pio run -e right -t upload
```

### XIAO nRF52840 Sense

```bash
cd Xiao_firmware
pio run -e left
pio run -e right
pio run -e left -t upload
pio run -e right -t upload
```

Firmware ทั้งสอง target ใช้ version `1.8.0`

## BLE Protocol

source of truth คือ [`docs/ble-protocol.md`](docs/ble-protocol.md) version `1.8.0`

ระบบใช้ lifecycle acknowledgement, sequence accounting, acquisition-health telemetry และ clock sync/drift mapping เพื่อให้ตรวจสอบความน่าเชื่อถือของข้อมูลได้ ไม่ใช้ RSSI เป็นตัวตัดสินว่าข้อมูลครบหรือไม่

## รูปแบบข้อมูล

### Mobile

Mobile เก็บข้อมูลตาม topic/trial/session ใน app documents และ export เป็น CSV/metadata/Excel/ZIP แบบมี version

### Windows

Windows ใช้ append-only `.waj` เป็น **authoritative record** ส่วน CSV เป็นไฟล์ที่ derive ออกมาภายหลัง incomplete `.open` journal สามารถ recover ได้

ค่า preview บน UI ไม่ใช่ research record หลัก

## Verification

```bash
# Mobile
cd app
flutter test
flutter analyze

# Windows Python stack (จาก root)
python -m pytest tools/pc_acquisition/tests tools/pc_gui/tests -q
python -m compileall -q tools/pc_acquisition tools/pc_gui
```

Automated test/simulation ไม่ถือเป็นหลักฐานของ RF จริง, ระยะ 0.5/2/5 m หรือ physical L/R start skew ต้องทดสอบกับบอร์ดจริงตาม physical acceptance plan

## Version ปัจจุบัน

| Component | Version |
|---|---:|
| Product | `1.8.0` |
| Flutter mobile | `1.8.0+9` |
| M5 firmware | `1.8.0` |
| XIAO firmware | `1.8.0` |
| BLE protocol | `1.8.0` |
| Windows installer | `1.8.0` |

ไฟล์ `VERSION` เป็น version กลางสำหรับ product/Windows packaging และมี automated test เช็ก version ที่ประกาศซ้ำในแต่ละ platform

## Project state และ branch

ข้อมูลสถานะล่าสุดถูกจัดรวมไว้ใน [`.project/`](.project/) เท่านั้น plan/prompt เก่าถูกลบออกเพราะ Git history เก็บประวัติทั้งหมดไว้อยู่แล้ว

งาน Windows ปัจจุบันอยู่บน branch `codex/pc-version` และ **ห้ามนำเข้า `main`** จนกว่าจะมีคำสั่งชัดเจนให้ทำ

## License

Proprietary — สงวนลิขสิทธิ์ทั้งหมด โปรเจกต์นี้เป็นงานวิจัย กรุณาติดต่อ maintainer ก่อนนำไปใช้ใหม่
