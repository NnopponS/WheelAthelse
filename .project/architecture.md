# WheelAthlete — Architecture (Phase 1: Data Collection)

## High-level diagram

```
  [ล้อซ้าย]                    [ล้อขวา]
 M5StickCPlus2 (L)            M5StickCPlus2 (R)
  IMU MPU6886                  IMU MPU6886
   │ accel xyz, gyro xyz        │ accel xyz, gyro xyz
   │ @ configurable Hz          │ @ configurable Hz
   └────── BLE GATT ────┐  ┌──── BLE GATT ──────┘
                        ▼  ▼
                ┌──────────────────────┐
                │   Flutter App         │
                │  (iOS + Android)      │
                │                       │
                │  - BLE manager (2 conn)│
                │  - Packet parser       │
                │  - Realtime display    │
                │  - Recorder + timestamp│
                │  - Mark event (sync)   │
                │  - CSV export/share    │
                └───────────┬───────────┘
                            │
                            ▼
                      session_*.csv
                            │
              (เฟสถัดไป) ───┘──► Python: train model
                            ▲
              กล้อง (gold standard) ถ่ายแยก
              → align ทีหลังด้วย mark event
```

## Components / Modules

### 1. Firmware (M5StickCPlus2) — `firmware/`
- **Platform:** PlatformIO + Arduino framework, ESP32
- **Libraries:** `M5Unified` (IMU + จอ), `NimBLE-Arduino` (BLE ประหยัด RAM)
- **หน้าที่:**
  - อ่าน IMU (accel x/y/z, gyro x/y/z) ที่ sampling rate ปรับได้ (50/100/200 Hz)
  - **ใช้ data-ready interrupt + hardware FIFO ของ MPU6886** (ไม่ใช่ polling เปล่าๆ)
    เพื่อให้ sampling interval แม่นและข้อมูลไม่หายตอน BLE สะดุด
  - แนบ timestamp ของ device (micros()) ในแต่ละ sample
  - แพ็คเป็น binary packet ส่งผ่าน BLE notify
  - รับคำสั่ง config (sample rate, start/stop, sync, scheduled start) ผ่าน BLE write
  - **scheduled synchronized start + เสียง beep 3-2-1** ก่อนเริ่ม (ดูหัวข้อ Time Sync)
  - แสดงสถานะบนจอ (connected, recording, battery, sample count, countdown)
  - ระบุตัวเอง L หรือ R (ตั้งผ่าน config หรือ build flag)

#### สถาปัตยกรรม acquisition ใน firmware (กันข้อมูลหาย)
```
[MPU6886] --data-ready INT--> ISR (set flag / drain FIFO)
                                  │
                          drain FIFO → ใส่ ring buffer / FreeRTOS queue
                                  │  (Core 0)
                                  ▼
                      BLE task อ่าน queue → batch → notify  (Core 1)
```
- ESP32 มี 2 core → แยก acquisition (อ่าน IMU/FIFO) ออกจาก BLE transmission
  ด้วย FreeRTOS task + queue → BLE ช้า/สะดุด ก็ไม่ทำให้ sampling เพี้ยนหรือข้อมูลหาย
- ISR ทำงานสั้นที่สุด (set flag / อ่าน FIFO count) แล้วให้ task หลัก drain
- ถ้า queue เต็ม (BLE หลุดนาน) → นับ drop count ใส่ meta เพื่อรู้ว่ามี gap

### 2. Mobile App (Flutter) — `app/`
- **Platform:** Flutter (iOS + Android)
- **Libraries:** `flutter_blue_plus` (BLE), `riverpod` (state), `csv`, `share_plus`, `path_provider`, `fl_chart`, `google_fonts`
- **Design:** มี design system / theme เป็นของตัวเอง (สี, typography, component) — UI ต้องสวย, อ่านง่าย, ใช้กลางแดดในสนามได้ (ดูหัวข้อ Design ด้านล่าง)
- **หน้าที่:**
  - สแกน + เชื่อม BLE พร้อมกัน 2 ตัว (L/R)
  - parse binary packet → IMU sample objects
  - แสดงค่า realtime (กราฟ/ตัวเลข) สวยงาม
  - ตั้ง sample rate + **synchronized start/stop** recording ทั้ง 2 ตัวพร้อมกัน
  - **Clock sync engine**: map ข้อมูล 2 ล้อเข้าสู่ timeline เดียวกันแบบสมบูรณ์ (ดูหัวข้อ Time Sync)
  - บันทึกลง buffer พร้อม app timestamp + device timestamp + synced timestamp
  - ปุ่ม "Mark Event" สร้าง sync marker (สำหรับ align กับวิดีโอ)
  - จัดเก็บเป็น **โฟลเดอร์ตามเรื่อง + รอบการทดลอง** (ดูหัวข้อ Storage)
  - export CSV + share ออกจากเครื่อง

### 3. Data format (CSV)
ไฟล์ต่อ session (ไฟล์รวม เรียงตาม synced timeline, มีคอลัมน์ `wheel`):
```
columns: seq, wheel, timestamp_app_ms, timestamp_device_us, timestamp_synced_ms, ax, ay, az, gx, gy, gz, marker
```
- `seq` = ลำดับ packet จาก firmware (ใช้ตรวจ packet loss)
- `timestamp_app_ms` = เวลาบนมือถือตอนรับ (epoch ms) — มี jitter จาก BLE
- `timestamp_device_us` = micros() บน M5 — ใช้คำนวณ interval จริงในแต่ละตัว
- `timestamp_synced_ms` = **เวลาบน common timeline หลังแก้ offset/drift** — ใช้จับคู่ 2 ล้อ + กล้อง (คอลัมน์หลักสำหรับ train model)
- `marker` = 1 เมื่อกด Mark Event, 0 ปกติ
- มีไฟล์ `session_<id>_meta.json`: ผู้ทดสอบ, วันเวลา, sample rate, sync quality (offset/drift residual), หมายเหตุ, ชื่อไฟล์วิดีโอกล้อง

### 4. Time Sync — ทำให้ 2 ล้อ sync กันแบบสมบูรณ์
ปัญหา: 2 ล้อเป็น M5 คนละตัว นาฬิกา (micros) ไม่ตรงกันและ drift, BLE notify มี latency/jitter
ต่างกันแต่ละ connection → ใช้ app timestamp ดิบๆ ไม่แม่นพอ

**Common reference = นาฬิกามือถือ** (ไม่ใช้ UTC จริง — ไม่ต้องมี NTP/RTC)
มือถือคุยกับทั้ง 2 ตัวอยู่แล้ว จึงเป็น reference กลางที่ดีและแม่นที่สุด

แนวทาง (clock-offset estimation แบบ NTP/PTP-lite ผ่าน BLE):
1. **Offset estimation:** app ส่ง "sync ping" ไปแต่ละ device, device echo ค่า `t_device_us` ของตัวเอง
   กลับมา. app วัด round-trip → ประเมิน offset ระหว่าง device clock (micros) กับนาฬิกามือถือ
   (เก็บค่าที่ round-trip ต่ำสุดเพื่อลด noise) — ทำตอนเริ่ม + ซ้ำเป็นช่วงระหว่าง recording
2. **Drift correction:** เก็บคู่ (t_device_us, t_app_ms) หลายจุด → fit linear (slope = อัตรา drift)
   → แปลงทุก sample เป็น `timestamp_synced_ms` บน common timeline (นาฬิกามือถือ)
3. **Scheduled synchronized start (กดเริ่มแล้ว 2 ตัวเริ่มพร้อมกันจริง):**
   - app รู้ offset ของแต่ละ device แล้ว → กำหนด `T_start = now_phone + 5s` (นับถอยหลัง 5 วิ)
   - แปลง `T_start` เป็น local micros ของแต่ละ device → ส่งคำสั่ง scheduled start (target_start_us)
   - แต่ละ device เริ่มเก็บ ณ instant เดียวกันบน timeline มือถือ (คลาดเคลื่อนเท่า offset error เท่านั้น)
   - ระหว่างนับถอยหลัง: ทั้ง 2 device ส่งเสียง **beep 3-2-1** จากลำโพง M5 พร้อมกัน
4. **Beep = audio sync marker:** เสียง beep ตอนเริ่มจะถูกอัดในวิดีโอกล้องด้วย + เกิด event ที่รู้เวลาแน่นอน
   ใน IMU/log → ใช้ align วิดีโอ↔IMU ได้แม่นโดยไม่ต้องเคาะล้อ (ใช้คู่กับ Mark Event ได้)
5. **Cross-check:** Mark Event / การเคาะล้อ ใช้ verify เพิ่มว่า 2 ล้อ + กล้อง align กันจริง
6. **(option) Export resampling:** resample/interpolate ทั้ง 2 ล้อเป็น grid เวลาเดียวกัน
   (เช่น ทุก 10ms) เพื่อให้แต่ละแถวมีค่า L/R ที่เวลาเดียวกัน — ทำตอน export

วัดคุณภาพ sync: residual จาก linear fit, ความต่างเวลา marker/beep ระหว่าง 2 ล้อ (ควร < 1 sample interval)

### 5. Storage — จัดเก็บเป็นโฟลเดอร์ตามเรื่อง + รอบการทดลอง
ตอนจะบันทึก ผู้ใช้เลือก/สร้าง "เรื่องที่เก็บ" (topic/subject) และระบบจัดเลข "รอบ (trial)" อัตโนมัติ:
```
WheelAthleteData/
└── <topic>/                      # เช่น "sprint_test", "athlete_A", "calibration_01"
    ├── topic_meta.json           # คำอธิบายเรื่อง, ผู้ทดสอบ, วันที่สร้าง
    └── trial_<NN>/               # รอบที่เท่าไหร่ (auto-increment: trial_01, trial_02, ...)
        ├── session_<id>.csv
        └── session_<id>_meta.json
```
- เลือก topic เดิมที่มีอยู่ หรือสร้างใหม่ ก่อนเริ่ม recording
- trial number เพิ่มอัตโนมัติต่อ topic (กันชนกัน, ผู้ใช้ override ได้)
- หน้า browse: topic → trial → session, ดู/แชร์/ลบได้

## BLE Protocol (สัญญาcontract ระหว่าง firmware ↔ app)

**Service UUID:** `0xWSEN` (กำหนดใน subtask #1)

| Characteristic | UUID | Type | Payload |
|---|---|---|---|
| IMU Data | TBD | Notify | binary packet (ดูล่าง) |
| Control | TBD | Write | `{cmd: start/stop/set_rate/sync_ping, rate: Hz, t_app: ..., target_start_us: ...}` |
| Sync | TBD | Notify/Indicate | echo `t_device_us` ตอบ sync_ping (สำหรับ clock-offset estimation) |
| Info | TBD | Read | wheel id (L/R), fw version, scale factor |

**IMU binary packet (little-endian):**
```
[uint32 seq][uint32 t_device_us][int16 ax][int16 ay][int16 az][int16 gx][int16 gy][int16 gz]
```
- ส่งแบบ batch หลาย sample/notify เพื่อลด BLE overhead (เช่น 5-10 sample ต่อ notify)
- scale factor (LSB→g, LSB→dps) ระบุใน Info characteristic หรือเอกสาร

## Design (UI ต้องสวย)
- มี design system: color palette (โหมดสว่าง/มืด + contrast สูงสำหรับกลางแดด), typography, spacing scale
- reusable component: connection card (L/R), live metric tile, record button, marker button, session list item
- L = สีหนึ่ง, R = อีกสี ชัดเจน สม่ำเสมอทั้งแอป
- realtime chart สวย (fl_chart) อ่านง่ายขณะเคลื่อนไหว
- empty state / loading / error state ออกแบบครบ
- ปุ่มหลัก (start/stop/mark) ใหญ่ กดง่ายตอนอยู่ในสนาม
- skill ที่ใช้ออกแบบ: `impeccable` + `ui-ux-pro-max`

## Data flow
1. App scan → เจอ 2 devices (L/R) → connect ทั้งคู่
2. App ทำ clock-offset estimation (sync_ping) กับทั้ง 2 device → ได้ offset/drift
3. ผู้ใช้เลือก/สร้าง topic + trial → ตั้ง sample rate
4. App ส่ง synchronized start → Firmware อ่าน IMU loop → batch → notify
5. App รับ notify → parse → คำนวณ timestamp_synced_ms → buffer + แสดง realtime
6. ผู้ใช้กด Mark Event ตอนเริ่ม/จบ trial (เคาะล้อให้เห็นในกล้องด้วย)
7. กด stop → app เขียน CSV + meta.json ลงโฟลเดอร์ topic/trial → share
8. (เฟสถัดไป) align CSV (synced timeline) กับวิดีโอด้วย marker → train model

## Tech stack สรุป
| ส่วน | Stack | Skill ที่ใช้ตอน build |
|---|---|---|
| Firmware | PlatformIO + Arduino C++ (ESP32) | `cpp-coding-standards` |
| App logic | Flutter / Dart | `dart-flutter-patterns` + `flutter-dart-code-review` |
| App UI/design | Flutter | `impeccable` + `ui-ux-pro-max` |
| Model (เฟสหน้า) | Python + PyTorch | `pytorch-patterns` + `mle-workflow` |

## Folder structure (monorepo)
```
WheelAthelse/
├── firmware/              # PlatformIO project (M5StickCPlus2)
│   ├── platformio.ini
│   ├── src/
│   └── README.md
├── app/                   # Flutter project
│   ├── lib/
│   ├── test/
│   └── pubspec.yaml
├── docs/
│   ├── ble-protocol.md    # contract firmware ↔ app
│   └── data-collection-protocol.md  # ขั้นตอนเก็บข้อมูลในสนาม
├── .project/              # สมองข้าม session (plan, progress, context)
└── README.md
```
