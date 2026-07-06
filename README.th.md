# WheelAthlete

**ระบบเก็บข้อมูลการเคลื่อนไหววีลแชร์ด้วย IMU** — เก็บข้อมูล accelerometer + gyroscope
ดิบจากล้อทั้งสองข้างและ sync กับวิดีโอกล้อง (gold standard) แทนการใช้ 3D Motion Capture
หลายกล้องที่แพงและไม่พกพาได้

> **สถานะ:** `v0.1.0` — Data Collection MVP (pre-release)
> **ภาษา:** [English](README.md) · [ภาษาไทย](README.th.md)

---

## สารบัญ

- [ภาพรวม](#ภาพรวม)
- [ฟีเจอร์ที่ใช้ได้ใน v0.1.0](#ฟีเจอร์ที่ใช้ได้ใน-v010)
- [ฟีเจอร์ที่ยังไม่มีใน v0.1.0](#ฟีเจอร์ที่ยังไม่มีใน-v010)
- [สถาปัตยกรรม](#สถาปัตยกรรม)
- [อุปกรณ์ที่ต้องเตรียม](#อุปกรณ์ที่ต้องเตรียม)
- [โครงสร้าง Repository](#โครงสร้าง-repository)
- [Build & Flash — Firmware](#build--flash--firmware)
- [Build & Run — Mobile App](#build--run--mobile-app)
- [รูปแบบข้อมูล](#รูปแบบข้อมูล)
- [การ Sync เวลา](#การ-sync-เวลา)
- [BLE Protocol](#ble-protocol)
- [ขั้นตอนเก็บข้อมูลในสนาม](#ขั้นตอนเก็บข้อมูลในสนาม)
- [การทดสอบ](#การทดสอบ)
- [Roadmap](#roadmap)
- [License](#license)

---

## ภาพรวม

WheelAthlete เปลี่ยน M5StickCPlus2 ราคาถูก 2 ตัว เป็นระบบเก็บข้อมูล IMU
สำหรับ biomechanics กีฬาวีลแชร์ระดับงานวิจัย แต่ละตัวติดบนล้อข้างหนึ่ง
แล้วส่งข้อมูล IMU 6 แกนแบบ synchronized ผ่าน BLE ไปยังแอป Flutter
แอปบันทึก session คำนวณ quality metrics และ export เป็น CSV/Excel
เพื่อเอาไป train model ในเฟสถัดไป

ระบบนี้แทนการตั้งกล้อง 3D Motion Capture ที่แพงและขนย้ายยาก ด้วยชุดพกพา
ใช้แบตเตอรี่ เอาใส่กระเป๋าเล็กได้ โทรศัพท์เครื่องเดียวทำหน้าที่เป็น
"นาฬิกากลาง" ให้ล้อทั้งสองข้าง ทำให้ไม่ต้องมี NTP หรือ RTC hardware

```
  [ล้อซ้าย]                    [ล้อขวา]
 M5StickCPlus2 (L)            M5StickCPlus2 (R)
  MPU6886 IMU                  MPU6886 IMU
   │ accel xyz, gyro xyz        │ accel xyz, gyro xyz
   │ @ 50/100/200 Hz            │ @ 50/100/200 Hz
   └────── BLE GATT ────┐  ┌──── BLE GATT ──────┘
                        ▼  ▼
                ┌──────────────────────┐
                │   Flutter App         │
                │  (iOS + Android)      │
                │  - BLE manager (x2)   │
                │  - Clock sync engine  │
                │  - Recorder + preview │
                │  - CSV/Excel export   │
                └───────────┬───────────┘
                            │
                            ▼
                      session_*.csv
                            │
              (เฟสถัดไป) ───► Python: train model
                            ▲
              กล้อง (gold standard) ถ่ายแยกต่างหาก
              → align ทีหลังด้วย beep 3-2-1 + mark events
```

---

## ฟีเจอร์ที่ใช้ได้ใน v0.1.0

นี่คือ release แรกที่ใช้งานได้จริง เป็น **Data Collection MVP** — แอปเก็บ
sync preview และ export ได้ แต่ยัง **ไม่มี** การ train หรือรัน machine-learning
model ใดๆ

### Firmware (M5StickCPlus2)
- อ่าน IMU MPU6886 ผ่าน data-ready interrupt + hardware FIFO
- sampling rate ปรับได้: 50 / 100 / 200 Hz
- BLE GATT server (NimBLE) 5 characteristics + Battery Service มาตรฐาน
- ส่ง IMU เป็น batch (สูงสุด 12 sample/packet ที่ MTU 247)
- คำสั่ง control: START, STOP, SET_RATE, SYNC_PING, SET_RANGE, BEEP,
  SET_NAME, SET_WHEEL, SET_UTC, RESET_SEQ
- scheduled synchronized start + นับถอยหลัง beep 3-2-1
- จอแสดงสถานะ: connection, recording, battery, sample count
- ระบุตัวเอง L/R ได้ทั้งตอน build และตอน runtime ผ่าน BLE
- เก็บ config (ชื่อ, ฝั่งล้อ, range) ถาวรใน NVS
- firmware version 0.2.0

### Mobile App (Flutter, iOS + Android)
- สแกน + เชื่อม BLE กับ M5StickCPlus2 พร้อมกัน 2 ตัว
- กำหนด L/R อัตโนมัติจาก Info characteristic ของบอร์ด
- Clock sync engine (NTP/PTP-lite ผ่าน BLE): offset + drift correction
  → timeline กลางในหน่วย UTC milliseconds
- แสดงค่า IMU realtime (6 ค่าต่อล้อ + sample/drop count)
- บันทึก session พร้อม synchronized start, countdown, beep
- เก็บ session แบบ topic → trial → session
- Protocol templates พร้อม target trial count (experiment tracker)
- session tags + ค้นหา/กรองในหน้า Browse
- หน้า session preview: scrub slider, กราฟ accel/gyro, สรุป stats
- quality badges (good / fair / poor / unknown) จาก drift residual RMS
- export CSV (ตาราง L/R แยก) และ Excel (.xlsx)
- แชร์ไฟล์ผ่าน OS share sheet
- theme light + dark ออกแบบให้อ่านได้กลางแดด
- app version 1.0.0+1

### เอกสาร
- BLE protocol spec (`docs/ble-protocol.md`) — source of truth เดียว
- ขั้นตอนเก็บข้อมูลในสนาม (`docs/data-collection-protocol.md`)
- เอกสารสถาปัตยกรรมใน `.project/` (Phase 1, 3, 4)

---

## ฟีเจอร์ที่ยังไม่มีใน v0.1.0

- ไม่มีการ train หรือรัน machine-learning model
- ไม่มี feedback ทาง biomechanics แบบ realtime ให้นักกีฬา
- ไม่มี cloud sync หรือ server backend (ข้อมูลอยู่ในเครื่องทั้งหมด)
- ไม่มีการ align วิดีโอ↔IMU อัตโนมัติ (ทำด้วยมือผ่าน beep + mark events)
- ไม่มี dashboard เปรียบเทียบหลายนักกีฬา/หลาย session
- firmware ไม่มี OTA update (flash ผ่าน USB เท่านั้น)

สิ่งเหล่านี้อยู่ในแผนเฟสถัดไป — ดู [Roadmap](#roadmap)

---

## สถาปัตยกรรม

ระบบมี 3 ชั้น:

### 1. Firmware (ESP32, Core 0 + Core 1)
- **Core 0:** อ่าน IMU — data-ready ISR ดึงข้อมูลจาก MPU6886 FIFO ใส่ FreeRTOS
  queue. sampling interval ถูกควบคุมด้วย hardware ไม่กระทบจาก BLE jitter
- **Core 1:** BLE task อ่าน queue แล้ว batch + notify ไปแอป ถ้า BLE สะดุด
  queue เต็ม → นับ `drop_count` แจ้งผ่าน Sync events
- pure logic (packet layout, scale tables, rate math) อยู่ใน
  `imu_types.h` / `ble_types.h` test บน host ได้โดยไม่ต้องมี hardware

### 2. Mobile App (Flutter + Riverpod)
- **BLE layer** (`lib/ble/`): abstract `BleRepository` + adapter
  `FlutterBluePlusBleRepository` + Fake สำหรับ unit test
- **State layer** (`lib/state/`): Riverpod 3.x Notifiers สำหรับ connection,
  IMU stream, clock sync, recording, preview, browse, protocol templates
- **Records layer** (`lib/records/`): session model, storage repository,
  protocol templates, session stats, quality badges
- **Export layer** (`lib/export/`): CSV + Excel exporters, resampler, share
- **UI layer** (`lib/ui/`): Connect, Live, Record, Browse, Session Preview,
  Experiment Tracker, Board Settings, Tag Editor
- **Theme** (`lib/theme/`): design system เป็นของตัวเอง — palette,
  typography (Inter + JetBrains Mono สำหรับตัวเลข tabular),
  WheelAthleteColors ThemeExtension (L=น้ำเงิน, R=ส้ม),
  light + dark high-contrast

### 3. ข้อมูล
- session เก็บในเครื่องที่ `WheelAthleteData/<topic>/trial_<NN>/`
- แต่ละ session = 1 CSV + 1 `session_<id>_meta.json`
- protocol templates เก็บใน `protocols.json` ข้าง data root

เอกสารสถาปัตยกรรมเต็ม:
- `.project/architecture.md` — Phase 1 (แกนเก็บข้อมูล)
- `.project/architecture-phase3.md` — Phase 3 (browse + protocol templates)
- `.project/architecture-phase4.md` — Phase 4 (session preview + quality)

---

## อุปกรณ์ที่ต้องเตรียม

| รายการ | จำนวน | หมายเหตุ |
|--------|-------|---------|
| M5StickCPlus2 | 2 | ล้อซ้าย + ล้อขวา |
| สาย USB-C | 2 | ชาร์จ + flash firmware |
| แบตเตอรี่สำรอง | 1 | ถ้าเก็บนานเกิน 30 นาที (แบต M5 ~80 mAh) |
| โทรศัพท์ iOS/Android | 1 | ลงแอป WheelAthlete |
| กล้องถ่ายวิดีโอ (gold standard) | 1 | แนะนำ 60+ fps มีไมโครโฟง |
| ขาตั้งกล้อง | 1 | ถ้ามี |
| กาว 3M VHB หรือยางรัด | — | ยึด M5 บนล้อ |
| ป้ายกำกับ L/R | 2 | ติดบน M5 ให้ชัด |

---

## โครงสร้าง Repository

```
WheelAthlete/
├── firmware/                 # PlatformIO project (M5StickCPlus2, ESP32)
│   ├── platformio.ini        # envs: left, right, native (host tests)
│   ├── src/
│   │   ├── main.cpp          # Entry point + task scheduling
│   │   ├── imu_types.h       # Pure logic: sample struct, scales, rate math
│   │   ├── imu_reader.{h,cpp}# MPU6886 FIFO + data-ready acquisition
│   │   ├── ble_types.h       # Pure logic: packet layout, command parsing
│   │   ├── ble_service.{h,cpp}# NimBLE GATT server
│   │   ├── config_store.{h,cpp}# NVS persistent config
│   │   ├── display.{h,cpp}   # M5 LCD status rendering
│   ├── test/                 # Unity host tests (env: native)
│   └── README.md
├── app/                      # Flutter project (iOS + Android)
│   ├── lib/
│   │   ├── main.dart
│   │   ├── ble/              # BLE repository, packet parser, device info
│   │   ├── state/            # Riverpod providers + clock sync engine
│   │   ├── records/          # Session model, storage, stats, quality, protocols
│   │   ├── export/           # CSV + Excel exporters, resampler, share
│   │   ├── ui/               # Connect, Live, Record, Browse, Preview, etc.
│   │   ├── widgets/          # Reusable components (chart, cards, badges)
│   │   └── theme/            # Design system (palette, typography, themes)
│   ├── test/                 # Unit + widget tests
│   ├── pubspec.yaml
│   └── README.md
├── docs/
│   ├── ble-protocol.md              # BLE contract (firmware ↔ app)
│   ├── data-collection-protocol.md # ขั้นตอนเก็บข้อมูลในสนาม
│   └── testing/                     # TDD evidence reports
├── tools/                    # Helper scripts
├── .project/                 # แผน, สถาปัตยกรรม, progress (cross-session)
├── README.md                 # ฉบับอังกฤษ
├── README.th.md              # ฉบับภาษาไทย (ไฟล์นี้)
└── .gitignore
```

---

## Build & Flash — Firmware

ต้องติดตั้ง [PlatformIO](https://platformio.org/) (VS Code extension หรือ CLI)

```bash
cd firmware

# build แต่ละล้อ
pio run -e left          # build ล้อซ้าย
pio run -e right         # build ล้อขวา

# flash ลง M5StickCPlus2 (เสียบ USB-C ก่อน)
pio run -e left -t upload     # flash ล้อซ้าย
pio run -e right -t upload    # flash ล้อขวา

# ดู serial debug
pio device monitor

# รัน host-side pure-logic tests (ไม่ต้องมี hardware)
pio run -e native            # build native test env
pio test -e native           # รัน Unity tests
```

build flag ตั้ง `WHEEL_ID` ตาม env:
- `env:left`  → `WHEEL_ID=0x4C` ('L')
- `env:right` → `WHEEL_ID=0x52` ('R')

ฝั่งล้อเปลี่ยนได้ตอน runtime ผ่านคำสั่ง `SET_WHEEL` BLE (เก็บถาวรใน NVS)

firmware version กำหนดใน `platformio.ini`:
`WheelAthlete_FW_MAJOR=0`, `WheelAthlete_FW_MINOR=2`, `WheelAthlete_FW_PATCH=0`

---

## Build & Run — Mobile App

ต้องติดตั้ง [Flutter](https://flutter.dev/) 3.x พร้อมอุปกรณ์หรือ emulator

```bash
cd app

flutter pub get
flutter run -d <device-id>          # รันบนมือถือ/emulator
flutter test                        # รัน unit + widget tests ทั้งหมด
flutter analyze                     # static analysis (strict config)

# build release
flutter build apk --release         # Android APK
flutter build appbundle --release   # Android App Bundle
flutter build ios --release         # iOS (ต้องมี macOS + Xcode)
```

dependencies หลัก (ดู `pubspec.yaml` สำหรับรายการเต็ม):
- `flutter_blue_plus ^2.3.9` — BLE
- `flutter_riverpod ^3.3.2` — state management
- `fl_chart ^1.2.0` — กราฟ
- `csv ^8.0.0`, `excel ^4.0.6` — export
- `share_plus ^13.2.0`, `path_provider ^2.1.6` — แชร์ไฟล์
- `file_picker 12.0.0-beta.7` — directory picker (pinned เพราะ share_plus compat)

app version: `1.0.0+1` (กำหนดใน `pubspec.yaml`)

---

## รูปแบบข้อมูล

แต่ละ session สร้าง 2 ไฟล์ที่ `WheelAthleteData/<topic>/trial_<NN>/`:

### `session_<id>.csv`
CSV แยกตาราง Left และ Right คอลัมน์:

| คอลัมน์ | Type | ความหมาย |
|--------|------|---------|
| `seq` | uint32 | ลำดับ sample จาก firmware (ใช้ตรวจ packet loss) |
| `wheel` | char | `L` หรือ `R` |
| `timestamp_app_ms` | uint64 | epoch ms บนมือถือตอนรับ (มี BLE jitter) |
| `timestamp_device_us` | uint32 | `micros()` บน M5 ตอน sample |
| `timestamp_synced_ms` | uint64 | **UTC epoch ms หลังแก้ offset/drift** — key หลักสำหรับ align 2 ล้อ + กล้อง |
| `ax, ay, az` | float | accel หน่วย g (raw × accel_scale) |
| `gx, gy, gz` | float | gyro หน่วย dps (raw × gyro_scale) |
| `marker` | 0/1 | 1 = กด Mark Event (legacy; v0.1.0 เป็น 0 หมด) |

### `session_<id>_meta.json`
metadata ของ session: ผู้ทดสอบ, วันเวลา, sample rate, sync quality
(offset + drift residual RMS ต่อล้อ), drop count, หมายเหตุ, ชื่อไฟล์วิดีโอ,
tags, `protocolTemplateId`

### `protocols.json`
protocol templates: `id`, `name`, `description`, `topicName`,
`targetTrialCount`, `sampleRateHz`, `createdAt`

---

## การ Sync เวลา

M5StickCPlus2 ทั้ง 2 ตัวมีนาฬิกา `micros()` คนละตัว และ drift ต่างกัน
BLE notify latency ก็ต่างกันทุก connection ใช้ timestamp มือถือดิบๆ ไม่แม่นพอ

**ทางแก้:** โทรศัพท์เป็น "นาฬิกากลาง" (คุยกับทั้ง 2 ล้ออยู่แล้ว) แอปรัน
NTP/PTP-lite ผ่าน BLE:

1. **Offset estimation** — แอปส่ง `SYNC_PING` พร้อม `t_app_ms`; firmware
   echo `t_device_us` กลับมา แอปวัด round-trip เก็บค่าที่ RTT ต่ำสุดเพื่อ
   ประมาณ offset
2. **Drift correction** — เก็บคู่ `(t_device_us, t_app_ms)` หลายจุด → fit
   linear (slope = อัตรา drift) → แปลงทุก sample เป็น
   `timestamp_synced_ms` บน timeline กลาง UTC
3. **Scheduled synchronized start** — แอปกำหนด `T_start = now + 5s`
   แปลงเป็น `micros()` ของแต่ละล้อ → ส่ง `START` พร้อม `target_start_us`
   ทั้ง 2 ล้อเริ่มพร้อมกันบน timeline มือถือ (คลาดเคลื่อน = offset error
   เท่านั้น ปกติ < 1 sample)
4. **Beep 3-2-1 audio marker** — ระหว่าง countdown ลำโพง M5 ทั้ง 2 ตัว beep
   ที่ T-3s, T-2s, T-1s, T-0 เสียงนี้อยู่ในวิดีโอกล้องด้วย → align
   วิดีโอ↔IMU ได้โดยไม่ต้องเคาะล้อ

sync quality รายงานเป็น **drift residual RMS หน่วย ms**:
- `< 2 ms` → good (เขียว)
- `2–5 ms` → fair (เหลือง)
- `> 5 ms` → poor (แดง)
- `null`  → unknown (เทา)

---

## BLE Protocol

contract เต็ม: [`docs/ble-protocol.md`](docs/ble-protocol.md) (version 1.1.0)

สรุป:

| Characteristic | UUID suffix | Properties | ทิศทาง | หน้าที่ |
|---|---|---|---|---|
| IMU Data | `a1b3` | Notify | FW → App | batch IMU samples (20 B ต่อ sample) |
| Control | `a1b4` | Write | App → FW | คำสั่ง (START, STOP, SET_RATE, ...) |
| Sync | `a1b5` | Notify + Indicate | FW → App | sync response + events |
| Info | `a1b6` | Read | FW → App | wheel ID, firmware version, ranges, scales |
| Config | `a1b7` | Read | FW → App | ชื่อบอร์ด, ฝั่งล้อ, ค่าที่เก็บถาวร |
| Battery Level | `2a19` | Read + Notify | FW → App | Battery Service มาตรฐาน (0x180F) |

Service UUID: `0000a1b2-0000-1000-8000-00805f9b34fb`

เอกสาร protocol เป็น source of truth เดียว — firmware และ app ต้อง
implement ตรงกัน ถ้าจะเปลี่ยนต้อง update เอกสารก่อน

---

## ขั้นตอนเก็บข้อมูลในสนาม

ขั้นตอนเต็ม: [`docs/data-collection-protocol.md`](docs/data-collection-protocol.md)

สรุปสั้น:
1. ชาร์จ M5 ทั้ง 2 ตัวให้เต็ม และ flash firmware ล่าสุด
2. ติด M5 บน hub ล้อทั้ง 2 ข้าง (แกน Z ตั้งฉากกับพื้นล้อ)
3. เปิดแอป → หน้า Connect → scan + connect ทั้ง 2 ตัว
4. รอ clock sync นิ่ง (residual < 2 ms)
5. เลือก protocol template (หรือ custom topic) ในหน้า Record
6. กดอัดวิดีโอกล้อง **ก่อน** กด Start ในแอป
7. กด Start → countdown 5 วิ + beep 3-2-1 → เริ่มเก็บข้อมูล
8. ระหว่างเก็บ ดู realtime metrics (Mark Event ถูกเอาออกใน v0.1.0 —
   beep + เสียงกล้องคือ sync source)
9. กด Stop → session saved → หน้า preview แสดง stats + กราฟ
10. export CSV/Excel จาก Browse หรือหน้า preview แล้วแชร์ผ่าน share sheet

---

## การทดสอบ

### Firmware
- host-side Unity tests (`pio test -e native`) ครอบ pure logic ใน
  `imu_types.h` และ `ble_types.h`: struct size, scale tables, rate math,
  FIFO byte parsing, timestamp interpolation, packet layout, command parsing
- Python unit tests (`firmware/test/test_imu_types.py`,
  `test_ble_types.py`) mirror C++ tests เพื่อ iterate เร็ว

### App
- unit tests สำหรับ BLE parsing, clock sync, recording, storage, stats,
  quality badges, protocol templates, export
- widget tests สำหรับทุก component และทุกหน้า
- `flutter analyze` รันด้วย strict config (strict-casts, strict-inference,
  raw-types, unawaited_futures = error)
- coverage reports ใน `docs/testing/`

---

## Roadmap

### เสร็จใน v0.1.0
- Phase 1: เก็บข้อมูล + calibration (firmware + app + CSV export)
- Phase 3: Browse, protocol templates, experiment tracker, session tags
- Phase 4: session preview page, quality badges, Excel export, UTC alignment

### แผน (ยังไม่อยู่ใน release นี้)
- **Phase 5:** Python pipeline — โหลด CSV, feature extraction, train
  classification/regression model สำหรับ biomechanical metrics
- **Phase 6:** feedback แบบ realtime ให้นักกีฬาระหว่าง train
- **Phase 7:** cloud sync + dashboard หลายนักกีฬา
- **Phase 8:** align วิดีโอ↔IMU อัตโนมัติ (beep detection + visual marker)
- **OTA firmware updates** ผ่าน BLE
- **รองรับ 4 ล้อ** สำหรับกีฬาในสนาม

---

## License

Proprietary — สงวนลิขสิทธิ์ทั้งหมด ดูที่ repository settings บน GitHub
เป็นโปรเจกต์งานวิจัย ติดต่อ maintainer ก่อนนำไปใช้ใหม่

---

**Release:** `v0.1.0` (pre-release) · **Firmware:** `0.2.0` · **App:** `1.0.0+1`
