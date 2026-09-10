# WheelAthlete

**แพลตฟอร์มเก็บข้อมูล IMU และวิเคราะห์การเคลื่อนไหวสำหรับงานวิจัยกีฬาวีลแชร์ โดยเน้นความเสถียรและความถูกต้องของข้อมูล**

WheelAthlete ซิงโครไนซ์เซนเซอร์ที่ล้อซ้ายและขวา บันทึกข้อมูลการเคลื่อนไหวแบบ research-grade และมี Windows application สำหรับเก็บข้อมูล ตรวจคุณภาพ จัดการผลลัพธ์ ส่งออกข้อมูล ดู diagnostics และวิเคราะห์ trajectory แบบ offline นอกจากนี้ระบบยังรองรับ IMU ตัวที่สามตำแหน่งกลางเก้าอี้ (`C`) สำหรับการเก็บข้อมูลและงานทดลอง

> **Release ปัจจุบัน:** `v1.8.2` — Windows-first
> **Windows application:** `1.8.2`
> **Firmware:** `1.8.2`
> **BLE protocol:** `1.8.0`
> **Mobile source:** `1.8.2+12` อยู่ในโหมด maintenance; release นี้ไม่เพิ่ม mobile source หรือ mobile binary ใหม่
> **ภาษา:** [English](README.md) | ไทย

## สถานะ Release

WheelAthlete 1.8.2 รวมงาน Windows application, firmware M5/XIAO, การรองรับเซนเซอร์ 3 ตัว, installer lifecycle, Results workflow, model bundle และระบบ release hardening ไว้ใน source line เดียว

โครงสร้าง branch สาธารณะตั้งใจให้เหลือเพียง:

- `main` — source หลักที่รวมงานทั้งหมดแล้ว
- `release/main-v1.8.2` — release line ที่ชี้ไปยัง commit 1.8.2 ที่ผ่านการตรวจสอบ

Tag ของ version เก่ายังคงเก็บไว้เพื่อ trace ประวัติได้ แต่ branch พัฒนา/release เก่าที่ merge เรียบร้อยแล้วไม่จำเป็นต้องแสดงอยู่ต่อ

### ตอนนี้ v1.8.2 เป็น source-only

GitHub Release v1.8.2 ปัจจุบันเผยแพร่เฉพาะ source code ก่อน เนื่องจากยังไม่มี trusted Windows Code Signing identity ที่ผ่านเงื่อนไข release pipeline

ไฟล์ Windows installer, portable ZIP และ `latest.json` จะเผยแพร่เมื่อระบบตรวจครบทั้ง RSA Code Signing certificate, Code Signing EKU, publisher subject ที่ตรงตามกำหนด, timestamp, executable components, generated uninstaller และ installer แล้ว `public_release_ready=true` เท่านั้น

ไฟล์ local unsigned ใช้สำหรับพัฒนาและทดสอบได้ แต่ไม่ถือเป็น public trusted build และ SHA-256 เพียงอย่างเดียวไม่สามารถสร้าง publisher trust หรือข้าม SmartScreen/Application Control policy ได้

## สิ่งที่อยู่ใน WheelAthlete 1.8.2

### WheelAthlete Windows Research Application

ตำแหน่ง: [`applications/wheelathlete_windows/`](applications/wheelathlete_windows/)

Windows application ใช้สถาปัตยกรรมแบบ 2 process:

- **Acquisition daemon** — ดูแล BLE, packet parsing, clock synchronization, sequence/loss accounting, append-only `.waj`, QC, recovery และ synchronized lifecycle
- **PySide6 GUI** — ดูแล Dashboard, Acquisition, Results, Diagnostics, export และ MODEL แบบ offline

GUI ไม่ใช่ authoritative raw-data path ดังนั้น chart ที่ช้า, model analysis หรือการ restart GUI ต้องไม่ทำให้เส้นทางบันทึก BLE สูญหายแบบเงียบ ๆ

ความสามารถสำคัญของ 1.8.2:

- Results แบบ Day -> Experiment -> Trial และเก็บ selection ด้วย session ID
- เลือกทั้งวัน / เลือกทั้งหมด / ล้าง selection และ batch export แบบไม่ซ้ำ
- ใช้ Windows QueryPerformanceCounter สำหรับ host timing ความละเอียดสูง
- แสดงสาเหตุ sensor fault อย่างชัดเจน เช่น sequence, queue, FIFO, malformed packet, fatal และ active retry
- ปิด acquisition daemon อย่างปลอดภัยและ finalize journal ก่อน upgrade/uninstall
- เก็บ recordings และ custom/seeded models ไว้ระหว่าง installer lifecycle
- รองรับ in-app update เมื่อมี trusted signed release และ `latest.json`
- รองรับ portable model bundle แบบ `wheelathlete-model.json` พร้อม validation

รันจาก source:

```bat
cd applications\wheelathlete_windows
run_wheelathlete_windows.bat
```

Demo mode:

```bat
run_wheelathlete_windows.bat --demo
```

ตำแหน่งข้อมูลหลักบน Windows:

```text
~/Documents/WheelAthlete/PC Sessions
~/Documents/WheelAthlete/Model
~/Documents/WheelAthlete/Logs
```

เอกสาร Windows แบบละเอียด: [`applications/wheelathlete_windows/README.md`](applications/wheelathlete_windows/README.md)

### Firmware และ Sensor

WheelAthlete ดูแล firmware 2 target:

| Target | Hardware | Roles | Version |
|---|---|---|---:|
| M5StickC Plus2 | ESP32 / M5StickC Plus2 | L / R / optional C | `1.8.2` |
| XIAO nRF52840 Sense | nRF52840 / LSM6DS3 | L / R / optional C | `1.8.2` |

ตำแหน่ง:

- [`hardware_firmware/m5stickc_plus2/`](hardware_firmware/m5stickc_plus2/)
- [`hardware_firmware/xiao_nrf52840_sense/`](hardware_firmware/xiao_nrf52840_sense/)

Role byte คือ `L=0x4C`, `R=0x52` และ optional chair-center `C=0x43`

การติดตั้ง C ปัจจุบันกำหนดให้ **+Z ชี้ลงพื้น** ส่วน X/Y ยังเป็นแกนจริงของบอร์ดจนกว่าจะวัดทิศ chair-forward/lateral อย่างชัดเจน XIAO C ใช้ไฟประจำตัว **สีเขียว** ส่วน M5 C ยังคงใช้สีเหลืองบนจอ Existing production trajectory model ยังใช้ข้อมูล L/R เท่านั้น

BLE specification หลัก: [`docs/ble-protocol.md`](docs/ble-protocol.md)

### MODEL แบบ Offline

Windows installed default ยังคงเป็น **Classical v1** ที่ใช้ L/R เท่านั้น ส่วน residual, Slalom และ hybrid เป็น research option ที่ต้องเลือกอย่างชัดเจน และไม่เปลี่ยน production default โดยอัตโนมัติ

Model ใหม่ที่นำเข้าแบบ portable ใช้ contract:

[`docs/model_analysis/MODEL_BUNDLES.md`](docs/model_analysis/MODEL_BUNDLES.md)

ไฟล์ `.waj` ยังคงเป็น authoritative research record ส่วน MODEL output, preview chart และ derived export ไม่ใช่สิ่งทดแทนความสมบูรณ์ของ raw recording หรือ physical reference validation

### สถานะ Mobile

Flutter Android/iOS source ที่มีอยู่เดิมยังเก็บไว้เพื่อ maintenance แต่ **การรวม v1.8.2 รอบนี้จะไม่เพิ่ม/แก้ mobile source สำหรับการ publish, ไม่สร้าง APK/AAB/IPA, ไม่มี mobile download และไม่มี mobile update offer**

ดังนั้น mobile ไม่ใช่ publication gate ของ v1.8.2 รอบนี้ หากจะกลับมาเผยแพร่ mobile ในอนาคตควรแยกเป็น release scope ที่ตรวจสอบต่างหาก

## โครงสร้าง Repository

```text
WheelAthelse/
├── applications/
│   ├── wheelathlete_windows/          # Windows v1.8.2 ที่ใช้งานหลัก
│   └── wheelathlete_mobile/           # mobile source สำหรับ maintenance
├── hardware_firmware/
│   ├── m5stickc_plus2/
│   └── xiao_nrf52840_sense/
├── assets/                            # shared product assets
├── docs/                              # BLE/model contracts, testing, wiki
├── release/                           # release notes + manifest tooling
├── scripts/                           # verification/hygiene tooling
├── .project/                          # สถานะวิศวกรรมปัจจุบัน
├── VERSION                            # coordinated product version
├── README.md
└── README.th.md
```

Generated builds, `.pio/`, Python cache, Flutter generated output, recordings, local engineering evidence และ local `BiWheel3D/` research repository จะไม่ถูกนำเข้า root source publication

## Data Integrity

Windows acquisition daemon เขียนข้อมูลหลักลง append-only `.waj` journal โดยถือเป็น authoritative recording ส่วน CSV และ summary เป็น derived output ที่สร้างใหม่ได้ และ `.open` journal ที่ยังไม่สมบูรณ์มี recovery path

Recording แบบ L/R-only ยังคง backward compatible ส่วน session ที่มี C ใช้ side code ของ C อย่างชัดเจน ระบบต้องไม่ decode C เป็น R และต้องไม่แทรก C เข้า legacy L/R model tensor โดยอัตโนมัติ

## ระบบอัปเดต Windows

Windows ที่ติดตั้งผ่าน installer ใช้ manifest:

```text
https://github.com/NnopponS/WheelAthelse/releases/latest/download/latest.json
```

เมื่อมี trusted signed release ระบบจะตรวจ semantic version, HTTPS URL ที่ต้องอยู่ใน GitHub Releases ของ repository นี้, exact byte size และ SHA-256 ก่อนเปิด installer และจะไม่เริ่มติดตั้ง update ขณะ Live preview, countdown หรือ recording ทำงานอยู่

v1.8.2 ที่เป็น source-only ในตอนนี้ **ไม่มี `latest.json`** จึงยังไม่มี update offer ไปยังเครื่องที่ติดตั้งอยู่

Release workflow ที่ [`.github/workflows/release.yml`](.github/workflows/release.yml) ใช้แบบ **manual workflow dispatch** โดยจะทดสอบ Windows, บังคับ trusted signing configuration, build/verify package, สร้าง `latest.json` และ publish เมื่อ release gate ผ่านเท่านั้น

รายละเอียด trust/release: [`release/README.md`](release/README.md)

## Build Windows Package

สิ่งที่ต้องมี:

- Python 3.10+
- PyInstaller
- Inno Setup 6

```bat
cd applications\wheelathlete_windows
packaging\windows\build_installer.bat
```

Generated package จะอยู่ใน `applications/wheelathlete_windows/release/` และถูก ignore จาก Git

## Verification

ตรวจ publication hygiene:

```bash
python scripts/verify_project.py
```

ตรวจ Windows application:

```bat
cd applications\wheelathlete_windows
python -m pytest tools\pc_gui\tests tools\pc_acquisition\tests -q
python -m compileall -q tools\pc_gui tools\pc_acquisition
```

Firmware host tests/builds ให้รันจากแต่ละ firmware target ด้วย test และ PlatformIO configuration ที่มีอยู่

Automated tests หรือการ build สำเร็จ **ไม่ใช่** หลักฐานยืนยัน RF throughput จริง, orientation จริง, synchronized timing ของ 3 บอร์ด หรือ trajectory accuracy สิ่งเหล่านี้ต้องใช้ physical/reference acceptance

## ขอบเขต Acceptance ปัจจุบัน

Source/software acceptance ของ 1.8.2 แยกออกจาก external gate 2 เรื่อง:

- **Trusted Windows signing** — ต้องมีก่อน publish Windows binaries และ update manifest
- **Final L/R/C physical acceptance** — รอจนกว่าจะมี hardware กลับมาใช้งานอีกครั้ง

XIAO C firmware 1.8.2 มี partial runtime evidence ที่ดี แต่ final Windows C record/QC/reopen/export และ simultaneous L/R/C bench run ยังไม่เสร็จ จึงไม่กล่าวว่า physical acceptance เสร็จสมบูรณ์

## เอกสารวิศวกรรม

- [`.project/STATUS.md`](.project/STATUS.md) — สถานะล่าสุดและ open gates
- [`.project/HANDOFF.md`](.project/HANDOFF.md) — ขั้นตอนต่อเนื่องที่ชัดเจน
- [`.project/architecture.md`](.project/architecture.md) — runtime/data/model boundaries
- [`.project/decisions.md`](.project/decisions.md) — active engineering decisions
- [`release/RELEASE_NOTES_1.8.2.md`](release/RELEASE_NOTES_1.8.2.md) — release summary

## Version Matrix

| Component | Version / status |
|---|---|
| Product release | `1.8.2` |
| Windows Research Application | `1.8.2` |
| M5StickC Plus2 firmware | `1.8.2` |
| XIAO nRF52840 Sense firmware | `1.8.2` |
| BLE protocol | `1.8.0` |
| Flutter mobile source | `1.8.2+12` — maintenance-only, ไม่อยู่ใน publication รอบนี้ |

ไฟล์ [`VERSION`](VERSION) ที่ root เป็น coordinated product version ที่ใช้กับ Windows packaging และ release validation

## License

Proprietary — การใช้งาน แจกจ่าย หรือแก้ไข source code ต้องได้รับอนุญาตจากผู้ดูแลโปรเจกต์
