# Phase 4 Context — Decisions

## D23: Session preview scope (2026-07-02)
- Full IMU chart (accel/gyro per axis, both wheels) with scrub/zoom
- Summary stats: duration, sample count, drop count, sync quality, mean/peak accel
- Scrubable timeline (slider)
- Export/share from preview page
- Entry from both Browse (tap session) and stopped view (Preview button)

## D24: Large session handling (2026-07-02)
- Lazy load chunks ตาม scrub position (เหมือน video player)
- ไม่โหลดทั้ง session ใน memory
- แต่ละ chunk ~500 samples → decimate เหลือ 80 points สำหรับ chart
- Stats คำนวณจาก meta + first chunk (mean/peak จาก chunk แรก, ไม่ใช่ full session — acceptable approximation)

## D25: Quality badge thresholds (2026-07-02)
- good = drift RMS < 2 ms (green)
- fair = drift RMS 2-5 ms (amber)
- poor = drift RMS > 5 ms (red)
- unknown = null (grey) — สำหรับ session เก่าที่ไม่มี sync data

## D26: Skipped features (2026-07-02)
- Clipboard sync helper — user บอก skip
- Video association — council เห็นว่าเพิ่ม complexity โดยไม่จำเป็น
- Cloud sync / backup — scope creep
- In-app data analysis — scope creep
- Multi-athlete management — scope creep
