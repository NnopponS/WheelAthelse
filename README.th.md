# WheelAthlete

**แพลตฟอร์มเก็บและวิเคราะห์ข้อมูล IMU จากล้อซ้าย–ขวา สำหรับงานวิจัยกีฬาวีลแชร์**

WheelAthlete ใช้เซนเซอร์ที่ล้อซ้ายและขวาเพื่อเก็บข้อมูล accelerometer และ gyroscope แบบซิงโครไนซ์ พร้อมแอปสำหรับมือถือและ Windows เพื่อใช้เก็บข้อมูลภาคสนาม ดูสถานะ ตรวจคุณภาพ จัดการ session ส่งออกข้อมูล และวิเคราะห์ trajectory แบบเสริม

> **Release ปัจจุบัน:** `v1.8.2` (Windows-first)
> **Mobile application:** source `1.8.2+12` อยู่ระหว่างบำรุงรักษาและยังไม่เปิดให้ใช้งาน
> **Firmware:** `1.8.2`
> **BLE protocol:** `1.8.0`
> **Windows package:** `1.8.2`
> **ภาษา:** [English](README.md) | ไทย

## WheelAthlete 1.8.2 สำหรับ Windows

รุ่น 1.8.2 เผยแพร่เฉพาะ Windows ส่วน source และ tests ของ Flutter iOS/Android ยังคงอยู่ใน repository เพื่อบำรุงรักษา แต่ไม่มีไฟล์ติดตั้ง ลิงก์ดาวน์โหลด หรือ mobile update ใน release นี้ แพ็กเกจ Windows สำหรับเผยแพร่ต้องมีลายเซ็น Authenticode ที่เชื่อถือได้; checksum หรือแพ็กเกจที่ไม่ได้เซ็นไม่สามารถแก้ download reputation warning หรือ Application Control error 4551 ได้

สถานะปัจจุบันอยู่ใน `.project/STATUS.md` และงานต่อเนื่องอยู่ใน `.project/HANDOFF.md` ข้อมูลวิจัย log และเอกสารเก่าถูกเก็บใน `.project/local/` ซึ่งไม่นำขึ้น Git ตรวจโครงสร้างก่อน commit ด้วย `python scripts/verify_project.py` การผ่าน source tests ไม่ใช่การรับรองความแม่นยำจากข้อมูลจริง

## สถาปัตยกรรมของผลิตภัณฑ์

Repository แบ่งเป็น 2 กลุ่มหลักอย่างชัดเจน:

1. **Applications** — ซอฟต์แวร์ที่ผู้ใช้ใช้งานโดยตรง
2. **Hardware & Firmware** — firmware สำหรับบอร์ดเซนเซอร์

มีแอปที่ดูแลอยู่ 2 ตัวเท่านั้น และควรใช้แอปเพียงตัวเดียวต่อ sensor pair ในเวลาเดียวกัน

| ส่วนประกอบ | ชื่ออย่างเป็นทางการ | Platform / Hardware | เทคโนโลยี | หน้าที่หลัก |
|---|---|---|---|---|
| Mobile | **WheelAthlete Mobile Application** | iOS, Android | Flutter / Dart | เชื่อมต่อ BLE, ดูข้อมูลสด, บันทึก session, จัดการและ export ข้อมูล |
| Windows | **WheelAthlete Windows Research Application** | Windows 10/11 | Python / PySide6 | เก็บข้อมูลแบบ reliability-first, QC, recovery, workflow งานวิจัย และ MODEL แบบเสริม |
| Firmware | **WheelAthlete M5StickC Plus2 Firmware** | M5StickC Plus2 / ESP32 | PlatformIO | อ่าน IMU และส่งข้อมูลผ่าน BLE |
| Firmware | **WheelAthlete XIAO nRF52840 Sense Firmware** | Seeed Studio XIAO nRF52840 Sense | PlatformIO | อ่าน IMU และส่งข้อมูลผ่าน BLE |

Flutter Windows, Flutter Web และ GUI รุ่นเก่าแบบ Tkinter ไม่อยู่ใน product surface ที่ดูแลแล้ว

## โครงสร้าง Repository

```text
WheelAthelse/
├── applications/
│   ├── wheelathlete_mobile/              # Flutter — iOS / Android
│   │   ├── android/
│   │   ├── ios/
│   │   ├── lib/
│   │   ├── test/
│   │   └── pubspec.yaml
│   │
│   └── wheelathlete_windows/             # Python / PySide6 — Windows
│       ├── tools/
│       │   ├── pc_acquisition/           # BLE acquisition daemon
│       │   └── pc_gui/                   # PySide6 UI + MODEL adapter
│       ├── packaging/
│       │   └── windows/                  # PyInstaller + Inno Setup
│       ├── run_wheelathlete_windows.bat
│       ├── build/                        # generated, ไม่เก็บใน Git
│       └── release/                      # generated, ไม่เก็บใน Git
│
├── hardware_firmware/
│   ├── m5stickc_plus2/                   # M5StickC Plus2 / ESP32 firmware
│   └── xiao_nrf52840_sense/              # XIAO nRF52840 Sense firmware
│
├── assets/                               # icon และ asset ที่ใช้ร่วมกัน
├── docs/                                 # BLE spec, test plan, protocol, wiki
├── .project/                             # สถานะและเอกสารวิศวกรรมของโปรเจกต์
├── VERSION                               # เวอร์ชันหลักของระบบ
├── README.md
└── README.th.md
```

ไฟล์ที่ generate จากการ build เช่น `build/`, `release/`, `.pio/`, Flutter generated files, Python cache และข้อมูล session ที่บันทึกจริง จะไม่ถูกเก็บใน Git

## ภาพรวมการทำงานของระบบ

```text
 IMU ล้อซ้าย                           IMU ล้อขวา
      |                                     |
      +--------------- BLE -----------------+
                         |
             +-----------+-----------+
             |                       |
             v                       v
 WheelAthlete Mobile       WheelAthlete Windows
 Application               Research Application
 Flutter / Dart             PySide6 GUI
 เชื่อม BLE โดยตรง              |
                                v
                          localhost IPC
                                |
                                v
                         Acquisition daemon
                         Bleak / WinRT BLE
                                |
                                v
                         append-only .waj journal
                         QC / recovery / CSV export
                                |
                                v
                         optional offline MODEL
```

Firmware ทั้งสองชนิดใช้ BLE contract เดียวกัน โดย specification หลักอยู่ที่ [`docs/ble-protocol.md`](docs/ble-protocol.md)

## Applications

### WheelAthlete Mobile Application

ตำแหน่ง: [`applications/wheelathlete_mobile/`](applications/wheelathlete_mobile/)

ความสามารถหลัก:

- เชื่อมต่อ sensor ล้อซ้ายและขวาผ่าน BLE
- แสดง Accel XYZ และ Gyro XYZ แบบ real-time
- synchronize clock และเวลาเริ่มบันทึกของสองบอร์ด
- จัดข้อมูลเป็น topic / trial / session
- ใช้ protocol template และ experiment tracking
- เพิ่ม tag, search, filter และ preview session
- แสดง QC, quality indicator และสถิติ
- export เป็น CSV, Excel, ZIP และ share ผ่านระบบปฏิบัติการ
- รองรับ Android และ iOS เท่านั้น

เริ่มใช้งาน:

```bash
cd applications/wheelathlete_mobile
flutter pub get
flutter run -d <device-id>
```

ตรวจสอบโค้ด:

```bash
cd applications/wheelathlete_mobile
flutter test
flutter analyze
```

Build release:

```bash
# Android
flutter build apk --release
flutter build appbundle --release

# iOS — ต้องใช้ macOS + Xcode
flutter build ios --release
```

### WheelAthlete Windows Research Application

ตำแหน่ง: [`applications/wheelathlete_windows/`](applications/wheelathlete_windows/)

Windows Application ใช้โครงสร้างแบบ 2 process เพื่อแยกเส้นทางเก็บข้อมูลจริงออกจาก UI:

- **Acquisition daemon** ดูแล BLE, packet parsing, synchronization, sequence/loss accounting, การเขียน journal, QC และ recovery
- **PySide6 GUI** ดูแลการควบคุม, status, preview, Results, Diagnostics, export และ MODEL แบบเสริม

GUI ไม่ใช่ authoritative raw-data path ดังนั้น chart ที่ช้า, model inference หรือการ restart GUI จะไม่ควรทำให้เส้นทางเก็บ raw BLE data หยุดหรือสูญหายโดยเงียบ

หน้าหลักของ Windows Application:

- **Dashboard** — การเชื่อมต่อบอร์ดและภาพรวมระบบ
- **Acquisition** — live preview และควบคุมการบันทึกแบบ synchronized
- **Results** — session ที่บันทึกแล้ว, QC, แก้ metadata, export และลบข้อมูล
- **MODEL** — วิเคราะห์ trajectory แบบ offline
- **Diagnostics** — ข้อมูลด้าน acquisition และ data integrity

เปิดจาก source:

```bat
cd applications\wheelathlete_windows
run_wheelathlete_windows.bat
```

โหมด Demo:

```bat
cd applications\wheelathlete_windows
run_wheelathlete_windows.bat --demo
```

ตำแหน่งข้อมูล default บน Windows:

- Sessions: `~/Documents/WheelAthlete/PC Sessions`
- GUI log: `~/Documents/WheelAthlete/Logs/wheelathlete-windows.log`
- Experiment presets: `~/Documents/WheelAthlete/experiments.json`

เอกสาร Windows แบบละเอียด: [`applications/wheelathlete_windows/tools/pc_gui/README.md`](applications/wheelathlete_windows/tools/pc_gui/README.md)

### MODEL แบบ Offline

หน้า `MODEL` ของแอป Windows ใช้ **BiWheel3D XY + Yaw current_best** ที่ฝังอยู่ในตัวแอปแล้ว ไม่ต้องใช้ PyTorch, ไฟล์ checkpoint `.pt/.pth`, model server หรือโฟลเดอร์ `BiWheel3D` ภายนอกในตอนใช้งานจริง

สำหรับการรันจาก source ให้ติดตั้ง NumPy ผ่านไฟล์ dependency นี้:

```bat
python -m pip install -r applications\wheelathlete_windows\tools\pc_gui\requirements-model.txt
```

ตัว Windows package จะรวม NumPy, calibration ของ current_best, runtime ที่จำเป็น และ MIT license ไว้ให้แล้ว การวิเคราะห์ทำแบบ offline และแยกจาก acquisition daemon โดยไฟล์ `.waj` ยังคงเป็นข้อมูลวิจัยต้นฉบับที่เชื่อถือได้

MODEL ใช้ข้อมูล Left/Right ที่บันทึกไว้ที่ 100 Hz แปลงหน่วยเป็น SI, รวม 5 samples ต่อหนึ่ง trajectory step ที่ 20 Hz แล้วคำนวณ XY และ net yaw ด้วยสูตร current_best ของ BiWheel3D รวมถึง yaw delay 27 frames ตาม recipe ปัจจุบัน

## Hardware & Firmware

Firmware ทั้งสอง target ใช้ WheelAthlete BLE contract เดียวกัน และรองรับ wheel identity, sampling rate, synchronized lifecycle, battery, sequence accounting, replay/recovery และ acquisition-health telemetry

### WheelAthlete M5StickC Plus2 Firmware

ตำแหน่ง: [`hardware_firmware/m5stickc_plus2/`](hardware_firmware/m5stickc_plus2/)

```bash
cd hardware_firmware/m5stickc_plus2

pio run -e left
pio run -e right

pio run -e left -t upload
pio run -e right -t upload
```

### WheelAthlete XIAO nRF52840 Sense Firmware

ตำแหน่ง: [`hardware_firmware/xiao_nrf52840_sense/`](hardware_firmware/xiao_nrf52840_sense/)

```bash
cd hardware_firmware/xiao_nrf52840_sense

pio run -e left
pio run -e right

pio run -e left -t upload
pio run -e right -t upload
```

## Build Windows Installer

สิ่งที่ต้องมี:

- Python 3.10+
- PyInstaller
- Inno Setup 6

Build portable package และ installer:

```bat
cd applications\wheelathlete_windows
packaging\windows\build_installer.bat
```

Output จะอยู่ที่:

```text
applications/wheelathlete_windows/release/
├── WheelAthlete-1.8.2-portable.zip
└── WheelAthleteSetup-1.8.2.exe
```

ทั้ง portable package และ installer จะ bundle `WheelAthleteDaemon.exe` ไปด้วย

รายละเอียด packaging: [`applications/wheelathlete_windows/packaging/windows/README.md`](applications/wheelathlete_windows/packaging/windows/README.md)

## ระบบอัปเดตแอปอัตโนมัติ

Flutter Mobile และ Python Windows ใช้ manifest กลางจาก GitHub Releases เดียวกัน:

```text
https://github.com/NnopponS/WheelAthelse/releases/latest/download/latest.json
```

ไฟล์ที่ดาวน์โหลดทุกไฟล์มีทั้งขนาดแบบ exact bytes และ SHA-256 อยู่ใน `latest.json` เพื่อให้ client ตรวจสอบก่อนติดตั้ง

- **Android:** release app ตรวจอัปเดตหลังเปิดแอปและทุก 6 ชั่วโมง ดาวน์โหลดเฉพาะ APK จาก HTTPS GitHub Release ของ repository นี้ ตรวจขนาดและ SHA-256 แล้วเปิด Android system installer ให้ผู้ใช้กดยืนยัน การอัปเดต APK ต่อเนื่องจำเป็นต้องใช้ release signing key เดิมทุกเวอร์ชัน ดังนั้น GitHub release workflow จะหยุดทันทีหากยังไม่ได้ตั้ง signing secrets
- **iOS:** ใช้ manifest เดียวกันสำหรับตรวจเวอร์ชัน แต่การติดตั้งต้องส่งต่อไป App Store/TestFlight เพราะ iOS ไม่อนุญาตให้แอปดาวน์โหลด binary แล้วแทนที่ตัวเองโดยตรง
- **Windows:** ตัวติดตั้งจริงที่ build ด้วย PyInstaller/Inno Setup จะตรวจอัปเดตหลังเปิดแอปและทุก 6 ชั่วโมง ดาวน์โหลด installer แล้วตรวจ size + SHA-256 ก่อน update AppId เดิมและเปิด WheelAthlete ใหม่อัตโนมัติ
- **ความปลอดภัยระหว่างเก็บข้อมูล:** Mobile และ Windows จะไม่เริ่มติดตั้งอัปเดตขณะ Live preview, countdown หรือ recording กำลังทำงาน

ระบบ release อัตโนมัติอยู่ที่ `.github/workflows/release.yml` เมื่อสร้าง tag `v<version>` ระบบจะ test/build ทั้ง Android และ Windows, สร้าง `latest.json` และ publish APK + EXE + manifest ใน GitHub Release เดียวกัน ดูรายละเอียดที่ [`release/README.md`](release/README.md)

> หมายเหตุ bootstrap: แอปเวอร์ชันเก่าที่ติดตั้งก่อนมี updater ไม่สามารถอัปเดตตัวเองได้ ต้องติดตั้ง updater-enabled release ครั้งแรกด้วยตนเอง 1 ครั้ง หลังจากนั้นจึงใช้อัปเดตในแอปได้

## Data Integrity

### Mobile

Mobile Application เก็บ session ตามโครงสร้าง topic / trial / session และสามารถ export เป็น CSV, metadata, Excel และ ZIP

### Windows

Acquisition daemon เขียนข้อมูลหลักลง append-only `.waj` journal โดยถือ journal นี้เป็น authoritative record ส่วน CSV และ summary เป็นข้อมูลที่ derive มาจาก journal

ไฟล์ `.open` ที่บันทึกไม่สมบูรณ์สามารถทำ recovery ได้

เมื่อ finalize แล้ว ระบบใช้ชื่อไฟล์ที่อ่านง่ายตาม topic / trial / athlete แต่ยังคง internal session UUID เดิมไว้

**ค่าที่เห็นใน preview, chart และผล MODEL ไม่ถือเป็น authoritative research record**

## BLE Protocol และ Synchronization

Specification หลัก: [`docs/ble-protocol.md`](docs/ble-protocol.md)

Protocol version ปัจจุบัน: `1.8.0`

กลไกด้าน reliability ที่สำคัญ:

- explicit recording lifecycle acknowledgement
- synchronized start ระหว่างล้อซ้ายและขวา
- clock synchronization และ drift mapping
- sequence accounting
- acquisition-health telemetry
- replay / recovery
- strict packet parsing และ QC

## Verification

Mobile Application:

```bash
cd applications/wheelathlete_mobile
flutter test
flutter analyze
```

Windows Application:

```bat
cd applications\wheelathlete_windows
python -m pytest tools\pc_acquisition\tests tools\pc_gui\tests -q
python -m compileall -q tools\pc_acquisition tools\pc_gui
```

Firmware:

```bash
cd hardware_firmware/m5stickc_plus2
pio run -e left
pio run -e right

cd ../xiao_nrf52840_sense
pio run -e left
pio run -e right
```

Automated test ไม่สามารถแทน physical acceptance test ที่ใช้บอร์ดจริง 2 ตัวภายใต้สภาพ RF จริงได้ทั้งหมด

## Version Matrix

| Component | Version |
|---|---:|
| Product release | `1.8.2` |
| WheelAthlete Mobile Application source | `1.8.2+12` (อยู่ระหว่างบำรุงรักษา; ยังไม่เปิดให้ใช้งาน) |
| WheelAthlete Windows Research Application | `1.8.2` |
| M5StickC Plus2 firmware | `1.8.2` |
| XIAO nRF52840 Sense firmware | `1.8.2` |
| BLE protocol | `1.8.0` |

ไฟล์ [`VERSION`](VERSION) ที่ root เป็น coordinated product version ที่ใช้กับ Windows packaging และ release validation

## เอกสารวิศวกรรม

- [`docs/`](docs/) — protocol, workflow ภาคสนาม, test plan และ wiki
- [`.project/`](.project/) — architecture, progress, engineering decision และสถานะล่าสุดของโปรเจกต์

## License

Proprietary — การใช้งาน แจกจ่าย หรือแก้ไข source code ต้องได้รับอนุญาตจากผู้ดูแลโปรเจกต์

## การอัปเดตซอฟต์แวร์อัตโนมัติ

WheelAthlete Mobile และ WheelAthlete Windows ใช้ manifest กลางชุดเดียวจาก GitHub Releases และตรวจสอบไฟล์ด้วยขนาดจริงและ SHA-256 ก่อนติดตั้ง:

```text
https://github.com/NnopponS/WheelAthelse/releases/latest/download/latest.json
```

- **Android:** release build จะตรวจอัปเดตอัตโนมัติ ดาวน์โหลด APK ที่ตรวจสอบแล้ว และเปิดหน้าติดตั้งของ Android ผู้ใช้ยังต้องกดยืนยันเอง และ APK ทุก public release ต้องเซ็นด้วย release key เดิมพร้อมเพิ่ม `versionCode` ทุกครั้ง
- **iOS:** ตรวจ manifest เดียวกัน แต่การติดตั้งต้องผ่าน App Store/TestFlight ตามข้อกำหนดของ iOS
- **Windows:** เวอร์ชันที่ติดตั้งด้วย PyInstaller/Inno Setup จะตรวจหลังเปิดโปรแกรมและทุก 6 ชั่วโมง ดาวน์โหลด installer ที่ตรวจ SHA-256 แล้ว ไม่ติดตั้งระหว่าง Live/Countdown/Recording จากนั้นปิดโปรแกรม อัปเดตแบบ silent และเปิด WheelAthlete กลับอัตโนมัติ ส่วน source/portable build จะไม่เขียนทับตัวเอง

`.github/workflows/release.yml` เป็นตัว build Android + Windows และสร้าง `latest.json` จาก binary จริง รุ่น production แรกที่มี updater ต้องติดตั้งด้วยตนเองหนึ่งครั้งสำหรับเครื่องที่ยังใช้รุ่นเก่าซึ่งไม่มีระบบ updater รายละเอียด signing และ release อยู่ที่ `release/README.md`
