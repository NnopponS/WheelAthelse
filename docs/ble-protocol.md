# WheelSense — BLE Protocol

**Contract ระหว่าง Firmware (M5StickCPlus2) ↔ Mobile App (Flutter)**

เอกสารนี้เป็น source of truth สำหรับทั้งสองฝั่ง — firmware และ app ต้อง implement
ตามนี้เป๊ะ ห้ามเปลี่ยนโดยไม่ update เอกสารนี้ก่อน

- เวอร์ชัน: `1.0.0` (subtask #1)
- อ้างอิง: `.project/architecture.md` หัวข้อ 4 (Time Sync) และหัวข้อ 5 (Storage)

---

## 1. GATT Service

| ชื่อ | UUID | Type |
|---|---|---|
| WheelSense Service | `0000a1b2-0000-1000-8000-00805f9b34fb` | Primary Service |

> ใช้ 128-bit UUID มาตรฐาน Bluetooth Base คือ `0000xxxx-0000-1000-8000-00805f9b34fb`
> โดย `xxxx = a1b2` คือ short handle ของ WheelSense (WSEN)

### 1.1 Characteristics

| Characteristic | UUID | Properties | ทิศทาง | ขนาดสูงสุด |
|---|---|---|---|---|
| IMU Data | `0000a1b3-0000-1000-8000-00805f9b34fb` | Notify | Firmware → App | up to MTU-3 |
| Control | `0000a1b4-0000-1000-8000-00805f9b34fb` | Write + Write Without Response | App → Firmware | up to 32 B |
| Sync | `0000a1b5-0000-1000-8000-00805f9b34fb` | Notify + Indicate | Firmware → App | 12 B |
| Info | `0000a1b6-0000-1000-8000-00805f9b34fb` | Read | Firmware → App | 16 B |

> App ควร request MTU 247 ตอน connect เพื่อให้ใส่ batch ได้มากขึ้น
> Firmware ต้อง support MTU exchange (NimBLE รองรับ default)

---

## 2. IMU Data Characteristic (Notify)

Firmware ส่ง batch ของ IMU samples ผ่าน notify 1 ครั้งต่อหลาย sample
เพื่อลด BLE overhead (เช่น 5–10 sample/notify ที่ 100 Hz)

### 2.1 Single sample (binary, little-endian, 20 bytes)

| Offset | Field | Type | หน่วย/ความหมาย |
|---|---|---|---|
| 0  | `seq`            | uint32 | ลำดับ sample ตั้งแต่ start (wrap ที่ 2^32) — ใช้ตรวจ packet loss |
| 4  | `t_device_us`    | uint32 | `micros()` บน M5 ณ ตอน sample (µs, wrap ที่ ~71.58 นาที) |
| 8  | `ax`             | int16  | accel X raw (LSB) — แปลงด้วย `accel_scale` จาก Info |
| 10 | `ay`             | int16  | accel Y raw |
| 12 | `az`             | int16  | accel Z raw |
| 14 | `gx`             | int16  | gyro X raw (LSB) — แปลงด้วย `gyro_scale` |
| 16 | `gy`             | int16  | gyro Y raw |
| 18 | `gz`             | int16  | gyro Z raw |

**ขนาด sample = 20 bytes**

### 2.2 Batch packet layout

```
[uint8 count][sample_0][sample_1]...[sample_{count-1}]
```
- `count`: 1–N (ขึ้นกับ MTU; ที่ MTU 247 → count สูงสุด = floor((247-3-1)/20) = 12)
- ทุก sample ใน batch ใช้ `seq` ต่อเนื่อง (seq+1, seq+2, ...) — app ใช้ตรวจ gap
- ถ้า queue ใน firmware เต็ม (BLE หลุดนาน) firmware ทิ้ง sample เก่า แล้วเพิ่ม `drop_count`
  ใน Info หรือส่ง sync event พิเศษ (ดู §4.4)

### 2.3 การแปลง raw → physical

```
accel_g  = raw * accel_scale      # accel_scale ขึ้นกับ range (±2g → 1/16384 g/LSB)
gyro_dps = raw * gyro_scale       # gyro_scale  ขึ้นกับ range (±2000 dps → 1/16.4 dps/LSB)
```
ค่า scale จริงอยู่ใน Info characteristic (§5) เพื่อให้ firmware เปลี่ยน range ได้ภายหลัง

---

## 3. Control Characteristic (Write)

App เขียนคำสั่งไป firmware ทุกคำสั่งเริ่มด้วย `uint8 cmd` ตามด้วย payload ของคำสั่งนั้น

### 3.1 Command set

| `cmd` | ชื่อ | Payload (หลัง cmd) | การตอบ |
|---|---|---|---|
| `0x01` | `START`            | `uint32 target_start_us` (0 = เริ่มทันที) | firmware เริ่ม acquisition ณ `target_start_us` (local micros) |
| `0x02` | `STOP`             | (ไม่มี) | firmware หยุด acquisition + flush batch สุดท้าย |
| `0x03` | `SET_RATE`         | `uint16 rate_hz` (50/100/200) | firmware เปลี่ยน sampling rate (ต้องหยุดก่อน) |
| `0x04` | `SYNC_PING`        | `uint32 t_app_ms` (เวลามือถือตอนส่ง) | firmware echo ผ่าน Sync characteristic (§4) |
| `0x05` | `SET_RANGE`        | `uint8 accel_range`, `uint8 gyro_range` | firmware เปลี่ยน IMU range + update Info |
| `0x06` | `BEEP`             | `uint8 count`, `uint16 period_ms` | firmware ส่งเสียง beep (sync marker ที่จอ/ลำโพง) |
| `0xFF` | `RESET_SEQ`        | (ไม่มี) | firmware รีเซ็ต `seq` กลับเป็น 0 |

> คำสั่งที่ไม่รู้จัก → firmware ส่ง Sync event `CMD_NACK` (§4.4)

### 3.2 Synchronized start (target_start_us)

เพื่อให้ 2 ล้อเริ่มพร้อมกันจริง:
1. App รู้ offset ของแต่ละ device จาก sync_ping (§4) แล้ว
2. App กำหนด `T_start_phone = now_phone + 5s` (นับถอยหลัง 5 วิ)
3. App แปลง `T_start_phone` เป็น local micros ของแต่ละ device:
   `target_start_us = (T_start_phone - t_app_ref_ms) * 1000 + offset_us + t_device_ref_us`
4. App ส่ง `START` พร้อม `target_start_us` ไปทั้ง 2 ตัว
5. Firmware วนรอจน `micros() >= target_start_us` แล้วเริ่ม acquisition + beep 3-2-1
6. คลาดเคลื่อนเท่ากับ offset error เท่านั้น (ควร < 1 sample interval)

### 3.3 Beep 3-2-1 (audio sync marker)

ระหว่างนับถอยหลัง firmware ส่งเสียง beep จากลำโพง M5:
- T-3s, T-2s, T-1s, T-0 (start) — 4 beep
- เสียง beep ถูกอัดในวิดีโอกล้องด้วย → ใช้ align วิดีโอ↔IMU ได้แม่นโดยไม่ต้องเคาะล้อ

---

## 4. Sync Characteristic (Notify / Indicate)

ใช้สำหรับ clock-offset estimation แบบ NTP/PTP-lite ผ่าน BLE

### 4.1 Sync response packet (12 bytes)

| Offset | Field | Type | ความหมาย |
|---|---|---|---|
| 0  | `t_app_ms`     | uint32 | echo ค่าที่ app ส่งมาใน SYNC_PING |
| 4  | `t_device_us`  | uint32 | `micros()` บน M5 ตอนรับ/ตอบ sync_ping |
| 8  | `seq_ping`     | uint32 | ลำดับ ping (เพิ่มทีละ 1 ต่อ device) — ใช้จับคู่ async |

### 4.2 Offset estimation (ฝั่ง app)

```
t1 = app ส่ง SYNC_PING (เก็บ t_app_ms = T1)
t2 = firmware รับ → อ่าน t_device_us = T2 → ส่ง Sync response
t3 = app รับ Sync response (T3 = now_phone)

RTT     = T3 - T1
offset  = T2 - (T1 + RTT/2)   # หน่วย µs (แปลง T1, T3 เป็น µs ก่อน)
```
- เก็บค่าที่ RTT ต่ำสุด (เช่น 10 ครั้ง เอา min-RTT) เพื่อลด noise
- ทำตอนเริ่ม + ซ้ำทุก ~30 วิ ระหว่าง recording เพื่อ track drift

### 4.3 Drift correction

เก็บคู่ `(t_device_us, t_app_ms)` หลายจุด → fit linear:
```
t_app_ms = a * t_device_us + b
```
- slope `a` = อัตรา drift (ควรใกล้ 1.0)
- ใช้ fit แปลงทุก sample เป็น `timestamp_synced_ms` บน common timeline (นาฬิกามือถือ)
- residual ของ fit ใช้เป็นตัววัด sync quality (เก็บใน `session_*_meta.json`)

### 4.4 Event notifications (Notify)

Sync characteristic ใช้ส่ง event พิเศษด้วย (flag ใน byte แรก):

| `event_id` (byte 0) | ชื่อ | Payload | ความหมาย |
|---|---|---|---|
| `0x00` | `SYNC_RESPONSE` | §4.1 | ตอบ SYNC_PING |
| `0x10` | `DROP_COUNT`    | `uint32 count` | จำนวน sample ที่ถูกทิ้งตั้งแต่ event ล่าสุด |
| `0x20` | `CMD_NACK`      | `uint8 cmd` | คำสั่งที่ไม่รู้จัก/ไม่ valid |
| `0x30` | `START_FIRED`   | `uint32 t_device_us` | ยืนยันว่าเริ่ม acquisition จริง ณ เวลานี้ |
| `0x40` | `STOP_FIRED`    | `uint32 t_device_us`, `uint32 last_seq` | ยืนยันว่าหยุด + seq สุดท้าย |

> App ใช้ `START_FIRED` / `STOP_FIRED` cross-check ว่า 2 ล้อเริ่ม/หยุดตรงกันจริง

---

## 5. Info Characteristic (Read, 16 bytes)

App อ่านครั้งเดียวตอน connect เพื่อรู้ capabilities ของ device

| Offset | Field | Type | ความหมาย |
|---|---|---|---|
| 0  | `wheel_id`     | uint8  | `0x4C` = 'L' (ล้อซ้าย), `0x52` = 'R' (ล้อขวา) |
| 1  | `fw_major`     | uint8  | firmware version major |
| 2  | `fw_minor`     | uint8  | firmware version minor |
| 3  | `fw_patch`     | uint8  | firmware version patch |
| 4  | `accel_range`  | uint8  | 0=±2g, 1=±4g, 2=±8g, 3=±16g |
| 5  | `gyro_range`   | uint8  | 0=±250, 1=±500, 2=±1000, 3=±2000 dps |
| 6  | `accel_scale`  | float32 | LSB → g (เช่น ±2g → 1/16384 ≈ 6.10e-5) |
| 10 | `gyro_scale`   | float32 | LSB → dps (เช่น ±2000 → 1/16.4 ≈ 6.10e-2) |
| 14 | `reserved`     | uint16 | 0x0000 (สำรอง) |

> `accel_scale` / `gyro_scale` เก็บเป็น float เพื่อให้ app ไม่ต้องเขียนตาราง lookup
> firmware คำนวณจาก range จริงที่ตั้งไว้ใน MPU6886

---

## 6. CSV Schema (export จาก app)

ไฟล์ต่อ session — ไฟล์รวมเรียงตาม synced timeline มีคอลัมน์ `wheel`:

```
seq,wheel,timestamp_app_ms,timestamp_device_us,timestamp_synced_ms,ax,ay,az,gx,gy,gz,marker
```

| คอลัมน์ | หน่วย | ความหมาย |
|---|---|---|
| `seq`                 | -     | ลำดับ packet จาก firmware (ตรวจ packet loss) |
| `wheel`               | L/R   | ล้อซ้ายหรือขวา |
| `timestamp_app_ms`    | ms    | เวลามือถือตอนรับ notify (epoch ms) — มี jitter จาก BLE |
| `timestamp_device_us` | µs    | `micros()` บน M5 — ใช้คำนวณ interval จริงในแต่ละตัว |
| `timestamp_synced_ms` | ms    | **เวลาบน common timeline หลังแก้ offset/drift** — คอลัมน์หลักสำหรับ train model |
| `ax, ay, az`          | g     | accel 3 แกน (แปลงจาก raw แล้ว) |
| `gx, gy, gz`          | dps   | gyro 3 แกน (แปลงจาก raw แล้ว) |
| `marker`              | 0/1   | 1 เมื่อกด Mark Event, 0 ปกติ |

### 6.1 meta.json (ต่อ session)

ไฟล์ `session_<id>_meta.json`:
```json
{
  "session_id": "20260628_153012_L",
  "topic": "sprint_test",
  "trial": 1,
  "wheel": "L",
  "started_at": "2026-06-28T15:30:12+07:00",
  "ended_at":   "2026-06-28T15:32:45+07:00",
  "sample_rate_hz": 100,
  "accel_range": 0,
  "gyro_range": 3,
  "sync": {
    "offset_us": -12345,
    "drift_slope": 1.00012,
    "residual_ms_rms": 0.42,
    "n_pings": 12,
    "min_rtt_ms": 8.3
  },
  "drop_count": 0,
  "last_seq": 14999,
  "markers": [
    {"t_synced_ms": 1234.5,  "label": "start_trial"},
    {"t_synced_ms": 14523.1, "label": "end_trial"}
  ],
  "video_file": "cam01_20260628_1530.mp4",
  "athlete": "athlete_A",
  "notes": ""
}
```

---

## 7. Storage — โครงสร้างโฟลเดอร์ topic/trial

```
WheelSenseData/
└── <topic>/                      # เช่น "sprint_test", "athlete_A", "calibration_01"
    ├── topic_meta.json           # คำอธิบายเรื่อง, ผู้ทดสอบ, วันที่สร้าง
    └── trial_<NN>/               # รอบที่เท่าไหร่ (auto-increment: trial_01, trial_02, ...)
        ├── session_<id>_L.csv
        ├── session_<id>_L_meta.json
        ├── session_<id>_R.csv
        └── session_<id>_R_meta.json
```

- ผู้ใช้เลือก topic เดิม หรือสร้างใหม่ ก่อนเริ่ม recording
- `trial_<NN>` auto-increment ต่อ topic (ผู้ใช้ override ได้)
- แต่ละ trial เก็บ 2 session (L + R) คู่กัน — ใช้ `session_id` เดียวกันเพื่อบอกว่าเป็นคู่กัน
- หน้า browse ใน app: topic → trial → session, ดู/แชร์/ลบได้

### 7.1 topic_meta.json

```json
{
  "topic": "sprint_test",
  "description": "ทดสอบการทำสปริ้นท์ 30m",
  "athlete": "athlete_A",
  "created_at": "2026-06-28T15:00:00+07:00",
  "trial_count": 3
}
```

---

## 8. Endianness & ข้อตกลงทั่วไป

- ทุก multi-byte field เป็น **little-endian** (ตรงกับ ESP32 + Dart default)
- String ใน characteristic ใช้ ASCII / UTF-8 โดยไม่มี null-terminator (ใช้ length prefix)
- ทุก notify อาจมาไม่ตรงลำดับได้น้อยมาก — app ต้องเรียงตาม `seq` และ detect gap
- ถ้า `seq` กระโดด → app บันทึก gap ใน meta (`drop_count` ประมาณการ) + แจ้งเตือนผู้ใช้
- Firmware ต้องส่ง batch สุดท้าย (flush) ตอน STOP แม้จะไม่เต็ม batch

---

## 9. สรุปสถานะการ implement

| ส่วน | Subtask | สถานะ |
|---|---|---|
| Service + Characteristic UUIDs | #1 | ✅ กำหนดในเอกสารนี้ |
| IMU binary packet + batch | #2, #3 | pending |
| Control commands (start/stop/set_rate/sync_ping/beep) | #3 | pending |
| Sync response + event notify | #3, #7 | pending |
| Info characteristic (wheel id, scale) | #3 | pending |
| CSV schema + meta.json | #9 | pending |
| Folder topic/trial | #8 | pending |

> เมื่อ implement จริง ให้ update ตารางนี้ + bump version ด้านบน
