# WheelAthlete — Data Collection Protocol (Phase 1)

> เอกสารนี้คือขั้นตอนเก็บข้อมูล IMU ในสนามให้ทำซ้ำได้ ใช้กับระบบ WheelAthlete
> Phase 1 (Firmware + Flutter App + CSV export) ที่สร้างใน subtask #1–#9

## สารบัญ
1. [อุปกรณ์ที่ต้องเตรียม](#1-อุปกรณ์ที่ต้องเตรียม)
2. [การติดตั้ง M5StickCPlus2 บนล้อ](#2-การติดตั้ง-m5stickcplus2-บนล้อ)
3. [การตั้งกล้อง Gold Standard](#3-การตั้งกล้อง-gold-standard)
4. [ขั้นตอนเก็บข้อมูล (Step-by-step)](#4-ขั้นตอนเก็บข้อมูล-step-by-step)
5. [Checklist ก่อนทดลอง](#5-checklist-ก่อนทดลอง)
6. [การตั้งชื่อไฟล์วิดีโอ](#6-การตั้งชื่อไฟล์วิดีโอ)
7. [การ Export และตรวจสอบ](#7-การ-export-และตรวจสอบ)
8. [การแก้ปัญหาเบื้องต้น](#8-การแก้ปัญหาเบื้องต้น)

---

## 1. อุปกรณ์ที่ต้องเตรียม

| รายการ | จำนวน | หมายเหตุ |
|--------|-------|---------|
| M5StickCPlus2 (เจ้าบ้าน firmware WheelAthlete) | 2 ตัว | L และ R |
| สาย USB-C | 2 เส้น | สำหรับชาร์จ + flash firmware |
| แบตเตอรี่สำรอง (M5StickC ใช้แบตในตัว ~80mAh) | 1 ก้อน | ถ้าเก็บนานเกิน 30 นาที |
| โทรศัพท์ iOS/Android | 1 เครื่อง | ลงแอป WheelAthlete |
| กล้องถ่ายวิดีโอ (gold standard) | 1 ตัว | แนะนำ 60+ fps, มีไมโครโฟง |
| ขาตั้งกล้อง | 1 | หรือจับด้วยมือก็ได้ |
| กาวหรือยางรัดสำหรับยึด M5 บนล้อ | ตามจำนวน | ดูหัวข้อ 2 |
| ป้ายกำกับ L/R | 2 | ติดบน M5 ให้ชัด |

---

## 2. การติดตั้ง M5StickCPlus2 บนล้อ

### 2.1 ตำแหน่ง
- ติดที่ **กลางล้อ** (hub) หรือ **ก้านล้อ** (spoke) แล้วแต่ชนิดรถ
- ทั้ง 2 ล้อติดที่ตำแหน่งเดียวกัน (สมมาตร)
- หลีกเลี่ยงตำแหน่งที่กระแทกพื้นโดยตรง

### 2.2 ทิศ axis
- **แกน Z (az)** ชี้ **ตั้งฉากกับพื้นผิวล้อ** (ทิศที่ล้อหมุนรอบ)
- **แกน X (ax)** ชี้ไปทาง **ด้านหน้า** (ทิศเคลื่อนที่)
- **แกน Y (ay)** ชี้ไปทาง **ด้านข้าง** (ขวามือ)
- ทั้ง 2 ล้อ ตั้งทิศเหมือนกัน

> ⚠️ ถ้าติดกลับด้าน ค่า accel จะกลับเครื่องหมาย แต่ train model ยังใช้ได้
> ถ้าทำตาม protocol เดียวกันทุกครั้ง

### 2.3 การยึด
- ใช้ **กาว double-sided 3M VHB** หรือ **ยางรัด (strap)**
- ต้องแน่นพอที่จะไม่ขยับระหว่างเคลื่อนไหว
- ทดสอบเขย่าดูก่อนเริ่ม — ถ้าขยับได้ ใช้กาวเพิ่ม

### 2.4 ระวัง balance
- ทั้ง 2 ล้อติดน้ำหนักเท่ากัน (M5 + กาว)
- ถ้าล้อเบี้ยว ปรับด้วย counterweight ฝั่งตรงข้าม
- ถ้าเป็นรถเข็น/วีลแชร์ ตรวจสอบว่าล้อหมุนได้อย่างอิสระ

---

## 3. การตั้งกล้อง Gold Standard

| พารามิเตอร์ | ค่าแนะนำ | เหตุผล |
|------------|---------|-------|
| มุม | ด้านข้าง (side view) เห็นล้อทั้ง 2 ข้าง | เห็นการเคลื่อนไหวชัด |
| ระยะ | 3–5 เมตร | กว้างพอเห็นทั้งตัว |
| FPS | ≥ 60 fps | จับ motion ละเอียด |
| ความละเอียด | ≥ 1080p | เห็น marker บนล้อได้ |
| แสง | แสงธรรมชาติหรือไฟส่องสว่าง | หลีกเลี่ยง backlight |
| เสียง | เปิดไมโครโฟง | จับ beep สำหรับ audio sync |
| Stabilization | ปิด (ถ้าใช้ขาตั้ง) | ป้องกัน motion blur |

> 💡 ถ้าใช้กล้องมือถือ: ตั้ง **60 fps + 4K** ถ้าได้ และ **ล็อก focus/ exposure**

---

## 4. ขั้นตอนเก็บข้อมูล (Step-by-step)

### 4.1 เตรียมอุปกรณ์ (5 นาที)
1. ชาร์จ M5StickCPlus2 ทั้ง 2 ตัวให้เต็ม (หรือ > 50%)
2. เช็คว่า firmware ล่าสุด flash แล้ว (ดู `firmware/README.md`)
3. เปิดแอป WheelAthlete บนโทรศัพท์
4. ติด M5 บนล้อทั้ง 2 ข้าง (ดูหัวข้อ 2)

### 4.2 เชื่อม BLE + Clock Sync (2 นาที)
1. ในแอป → หน้า **Connect**
2. กด **Scan** → เจอ `WheelAthlete-L` และ `WheelAthlete-R`
3. กด connect ทั้ง 2 ตัว
4. รอ **Clock Sync** ทำงานอัตโนมัติ (ส่ง sync ping หลายรอบ)
5. เช็คว่า sync quality นิ่งแล้ว (residual < 2 ms) — ดูในหน้า Live

### 4.3 เลือก Topic + Trial (1 นาที)
1. ไปหน้า **Record** (กดไอคอน ● ใน AppBar)
2. เลือก topic ที่มีอยู่ หรือกด **New Topic** สร้างใหม่
   - ตัวอย่าง: `sprint_test`, `athlete_A`, `calibration_01`
3. ระบบแสดง trial number อัตโนมัติ (เช่น `trial_01`)
4. (Optional) ตั้ง sample rate: 100 Hz (default) หรือ 50/200 Hz

### 4.4 เริ่มอัดวิดีโอกล้อง (30 วินาทีก่อน)
1. ตั้งกล้องตามหัวข้อ 3
2. กดอัดวิดีโอ **ก่อน** กด start ในแอป (เผื่อเวลา sync)
3. บอกชื่อไฟล์วิดีโอออกเสียง เช่น "sprint_test trial_01 session starting now"
   (เสียงนี้จะอยู่ในวิดีโอ ใช้ cross-check ได้)

### 4.5 เริ่ม Recording ( countdown + beep )
1. ในแอป กด **Start Recording**
2. ระบบนับถอยหลัง **5 วินาที** + **beep 3-2-1** จากลำโพง M5 ทั้ง 2 ตัว
   - เสียง beep นี้ **อยู่ในวิดีโอด้วย** = audio sync marker
   - ใช้ align วิดีโอ ↔ IMU ได้โดยตรง (ไม่ต้องเคาะล้อ)
3. หลัง beep สุดท้าย → ระบบเริ่มเก็บข้อมูลทั้ง 2 ล้อพร้อมกัน

### 4.6 ระหว่างเก็บข้อมูล
- ดูค่า realtime ในหน้า Record (sample count, marker count, elapsed time)
- กด **MARK** เพิ่ม sync marker ได้ตลอดเวลา (เช่น ตอนเริ่ม/จบ action)
  - แนะนำ: mark ตอนเริ่มเคลื่อนไหว + ตอนหยุด
  - (Optional) เคาะล้อเบาๆ ให้กล้องเห็น = cross-check เพิ่ม
- ถ้ามีปัญหา (BLE หลุด, แบตต่ำ) → กด **Stop** ทันที

### 4.7 หยุด Recording
1. กด **Stop Recording** ในแอป
2. ระบบหยุด IMU ทั้ง 2 ล้อ + เขียน CSV + meta.json
3. หน้าจอแสดง **"Session saved"** + สรุป (samples, markers, duration)
4. หยุดอัดวิดีโอกล้อง

### 4.8 Export + Share
1. ไปหน้า **Browse** (กดไอคอนโฟลเดอร์ใน AppBar)
2. เลือก topic → trial → session
3. กด **Share** (ไอคอน share) → เลือก AirDrop/Google Drive/Line/ฯลฯ
4. (Optional) เปิด resampling ถ้าต้องการ L/R ที่เวลาเดียวกัน
5. บันทึกชื่อไฟล์วิดีโอใน meta (กดแก้ไข session → ใส่ video file name)

---

## 5. Checklist ก่อนทดลอง

พิมพ์หรือเซฟ checklist นี้ ใช้ตรวจทุกครั้งก่อนเริ่ม:

```
□ แบต M5 ทั้ง 2 ตัว > 50%
□ Firmware ล่าสุด
□ M5 ติดบนล้อแน่น (เขย่าดู)
□ ทิศ axis ถูก (Z ตั้งฉากล้อ, X ไปข้างหน้า)
□ โทรศัพท์แบตเต็ม
□ แอปเปิดอยู่ + พื้นที่เครื่องพอ
□ กล้องแบตเต็ม + การ์ด SD ว่างพอ
□ กล้องตั้ง 60+ fps + เสียงเปิด
□ เชื่อม BLE 2 ล้อครบ
□ Clock sync นิ่ง (residual < 2 ms)
□ Sample rate ถูก (100 Hz default)
□ เลือก topic + ดู trial number
□ อัดวิดีโอกล้องก่อนกด start
□ บอกชื่อไฟล์วิดีโอออกเสียง
```

---

## 6. การตั้งชื่อไฟล์วิดีโอ

ตั้งชื่อไฟล์วิดีโอให้ตรงกับ session เพื่อให้ align ได้ง่าย:

```
<topic>_<trial>_<sessionId>_<YYYYMMDD_HHMMSS>.mp4
```

ตัวอย่าง:
```
sprint_test_trial01_abc123_20260629_143022.mp4
```

- `topic` = ชื่อ topic ในแอป
- `trial` = `trialNN` (เช่น `trial01`)
- `sessionId` = hex timestamp จากแอป (ดูในหน้า Browse)
- `YYYYMMDD_HHMMSS` = วันเวลาเริ่มอัด

> 💡 บันทึกชื่อไฟล์วิดีโอใน meta.json ผ่านแอป (แก้ไข session → ใส่ video file name)

---

## 7. การ Export และตรวจสอบ

### 7.1 Export CSV
1. หน้า Browse → topic → trial → session → Share
2. ไฟล์ CSV จะมี schema:
   ```
   seq,wheel,timestamp_app_ms,timestamp_device_us,timestamp_synced_ms,
   ax,ay,az,gx,gy,gz,marker
   ```
3. ไฟล์ meta.json จะมี: sessionId, topic, trial, datetime, sample rate,
   sync quality (offset/drift residual), sample/marker count, video file name

### 7.2 ตรวจสอบด้วย `tools/check_session.py`

```bash
python tools/check_session.py <path/to/session_*.csv>
```

สคริปต์จะ:
- **Plot** accel/gyro 2 ล้อบน `timestamp_synced_ms` (ดูว่า align กัน)
- **หา marker** และวัดความต่างเวลา marker ระหว่าง L/R (verify sync)
  - ควร < 1 sample interval (เช่น < 10 ms ที่ 100 Hz)
- **เช็ค effective sample rate** จริง + gap/packet loss/drop count
- (Optional) เทียบ beep ในไฟล์เสียงวิดีโอกับ marker ใน IMU

### 7.3 เกณฑ์ผ่าน
| ตัวชี้วัด | เกณฑ์ | วิธีดู |
|----------|-------|-------|
| Marker diff L/R | < 10 ms (ที่ 100 Hz) | check_session.py |
| Drift residual | < 2 ms RMS | meta.json |
| Effective sample rate | ±5% ของที่ตั้ง | check_session.py |
| Packet loss (seq gap) | < 1% | check_session.py |
| จำนวน sample | ใกล้ duration × rate | check_session.py |

ถ้าไม่ผ่าน → ดูหัวข้อ 8 แก้ปัญหา แล้วเก็บใหม่

---

## 8. การแก้ปัญหาเบื้องต้น

| อาการ | สาเหตุที่เป็นไปได้ | วิธีแก้ |
|-------|-------------------|--------|
| BLE หลุดบ่อย | รบกวนสัญญาณ / ไกลเกิน | ใกล้โทรศัพท์ < 2m, หลีกเลี่ยง WiFi แน่น |
| Sync residual สูง (> 5 ms) | BLE latency ไม่นิ่ง | รอ sync นานขึ้น (30 วิ), ลองเปลี่ยนตำแหน่ง |
| Sample rate ไม่ถึง | BLE throughput ไม่พอ | ลด rate เป็น 50 Hz, ลด batch size |
| แบตหมดเร็ว | อุณหภูมิสูง / BLE ทำงานหนัก | ชาร์จก่อน, ใช้แบตสำรอง |
| CSV มี gap ใหญ่ | Packet loss ระหว่าง BLE | ลดระยะ, ลด rate, เช็ค firmware FIFO |
| Marker diff L/R ใหญ่ | Clock drift ไม่ corrected | รอ sync นานขึ้น, เช็คว่า sync engine ทำงาน |
| วิดีโอไม่มีเสียง beep | ไมค์ปิด / ไกลเกิน | เปิดไมค์, วางกล้องใกล้ M5 พอสมควร |

---

## หมายเหตุ: Beep และ Audio Sync

เสียง beep 3-2-1 จากลำโพง M5StickCPlus2 ทั้ง 2 ตัว จะถูกอัดในวิดีโอกล้องด้วย
เพราะเริ่มอัดก่อนกด start ในแอป เสียงนี้ใช้ align วิดีโอ ↔ IMU ได้โดยตรง:

1. หาจังหวะ beep ในไฟล์เสียงวิดีโอ (ดู waveform peak)
2. หา marker แรกใน CSV (คอลัมน์ `marker = 1`)
3. ถ้าทั้ง 2 ตรงเวลากัน → sync สมบูรณ์ (ไม่ต้องเคาะล้อ)

การเคาะล้อ (tap wheel) ใช้เป็น **cross-check** เพิ่ม: กล้องเห็นการสั่น
ในวิดีโอ + IMU เห็น spike ใน accel → ยืนยันว่า align จริง

---

## อ้างอิง
- `architecture.md` — สถาปัตยกรรมระบบโดยรวม
- `docs/ble-protocol.md` — contract firmware ↔ app
- `tools/check_session.py` — สคริปต์ตรวจสอบ CSV
- `.project/lessons.md` — บันทึกปัญหา + วิธีแก้จากการพัฒนา
