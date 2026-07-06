# Architecture

> v0.1.0 — Data Collection MVP

## High-level topology

```
  [Left wheel]                [Right wheel]
 M5StickCPlus2 (L)           M5StickCPlus2 (R)
  MPU6886 IMU                 MPU6886 IMU
   │ accel xyz, gyro xyz       │ accel xyz, gyro xyz
   │ @ 50/100/200 Hz           │ @ 50/100/200 Hz
   └────── BLE GATT ────┐  ┌── BLE GATT ──────┘
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
              (future phase) ─► Python: train model
                            ▲
              Camera (gold standard) recorded separately
              → aligned later via beep 3-2-1 + mark events
```

## Firmware (ESP32)

### Core split
ESP32 has 2 cores — acquisition and BLE transmission are decoupled so BLE
stalls never distort sampling.

- **Core 0 — IMU acquisition**
  - MPU6886 data-ready interrupt fires when a sample is ready
  - ISR sets a flag and drains the hardware FIFO into a FreeRTOS queue
  - Sampling interval is hardware-timed, immune to BLE jitter
- **Core 1 — BLE transmission**
  - BLE task reads from the queue, batches samples, and notifies the app
  - If BLE stalls long enough for the queue to fill, `drop_count` is
    incremented and reported via Sync events

### Module map

| File | Role |
|------|------|
| `main.cpp` | Entry point, FreeRTOS task creation, Arduino loop |
| `imu_types.h` | Pure logic — `ImuSample` struct (20 B), scale tables, rate math, FIFO byte parsing, timestamp interpolation. Host-testable. |
| `imu_reader.{h,cpp}` | MPU6886 setup, FIFO drain, data-ready ISR, sampling task |
| `ble_types.h` | Pure logic — packet layout, command parsing, sync event encoding. Host-testable. |
| `ble_service.{h,cpp}` | NimBLE GATT server — service, characteristics, callbacks, batch notify |
| `config_store.{h,cpp}` | NVS persistent storage for board name, wheel ID, ranges |
| `display.{h,cpp}` | M5 LCD status rendering (connection, recording, battery, sample count) |

### Why pure logic in headers?
`imu_types.h` and `ble_types.h` contain only pure functions and structs
with no hardware dependencies. They are compiled into both the firmware
(ESP32) and the host-side Unity test environment (`env:native`), so the
same code is tested without hardware. Python mirrors in
`firmware/test/test_*.py` provide fast iteration.

## Mobile App (Flutter)

### Layered design

```
┌─────────────────────────────────────────────────────┐
│ UI layer (lib/ui/)                                  │
│   Connect · Live · Record · Browse · Preview ·      │
│   ExperimentTracker · BoardSettings · TagEditor     │
├─────────────────────────────────────────────────────┤
│ State layer (lib/state/) — Riverpod 3.x Notifiers   │
│   ble_providers · imu_providers · sync_engine ·     │
│   recording_providers · preview_providers ·         │
│   browse_providers · protocol_providers ·           │
│   experiment_tracker_providers · board_settings ·   │
│   home_providers · record_countdown                 │
├─────────────────────────────────────────────────────┤
│ Domain layer (lib/records/, lib/ble/, lib/export/)  │
│   SessionModel · StorageRepository · ProtocolRepo · │
│   SessionStats · QualityBadge · BleRepository ·     │
│   ImuPacketParser · SyncPacket · DeviceInfo ·       │
│   CsvExporter · ExcelExporter · Resampler           │
├─────────────────────────────────────────────────────┤
│ Adapters                                            │
│   FlutterBluePlusBleRepository (real BLE)           │
│   PathProviderStorageRepository (filesystem)        │
│   PathProviderProtocolRepository (filesystem)       │
└─────────────────────────────────────────────────────┘
```

### Why abstract repositories?
Every external dependency (BLE, filesystem) sits behind an abstract
interface with a Fake implementation. This keeps state logic fully
unit-testable without hardware or a real phone. The production adapter
(`FlutterBluePlusBleRepository`) is excluded from coverage because it
requires real BLE hardware — the field test is the integration test for it.

### Tabs (v0.1.0)
1. **Connect** — scan + connect to two M5StickCPlus2 modules
2. **Live** — realtime IMU display (6 metrics per wheel)
3. **Browse** — sessions by topic → trial → session, with search + tag filter
4. **Experiments** — protocol template dashboard with progress bars

Recording is a separate flow from the Record FAB; session preview opens
from Browse (tap session) or from the stopped-view after recording.

### Theme / design system
- Custom palette (`app_palette.dart`) + dimensions (`app_dimens.dart`)
- Typography: Inter for UI, JetBrains Mono for tabular metrics
- `WheelAthleteColors` ThemeExtension — L=blue, R=orange + semantic colors
- Light + dark high-contrast `ThemeData` (sunlight-readable)
- Reusable components in `lib/widgets/` (chart, cards, badges, buttons)

## Data flow

```
User picks protocol template on Record tab
  → SessionConfig carries protocolTemplateId + topic + sampleRate
  → Start → countdown 5s + beep 3-2-1 → both wheels begin acquisition
  → Firmware streams IMU batches over BLE notify
  → App parses batches, applies clock sync → BufferedSample with
    timestamp_synced_ms (UTC epoch ms)
  → Stop → flush + write CSV + meta.json
  → Session appears in Browse with quality badge
  → User opens preview → scrub chart + view stats
  → User exports CSV/Excel → shares via OS sheet
```

## Storage layout

```
<app documents>/
└── WheelAthleteData/
    ├── <topic>/
    │   ├── topic_meta.json
    │   └── trial_<NN>/
    │       ├── session_<id>.csv
    │       └── session_<id>_meta.json   (+tags, +protocolTemplateId)
    └── protocols.json
```

## Key design decisions

1. **Phone as common clock** — no NTP, no RTC. The phone talks to both
   wheels already, so it's the cheapest accurate reference.
2. **Hardware FIFO + data-ready interrupt** — sampling interval is
   deterministic regardless of BLE latency. Queue absorbs BLE jitter.
3. **Pure logic in headers** — same code tested on host (Unity + Python)
   and on target (ESP32). Catches protocol bugs before flashing.
4. **Abstract repositories + Fakes** — state logic is fully unit-testable
   without hardware. Production adapters are thin and field-tested.
5. **Beep 3-2-1 as audio sync marker** — recorded by the camera, so
   video↔IMU alignment doesn't require tapping the wheel.
6. **UTC milliseconds as the primary timestamp** — `timestamp_synced_ms`
   is the single key for cross-wheel + cross-camera alignment.

## References
- `.project/architecture.md` — Phase 1 (data collection core)
- `.project/architecture-phase3.md` — Phase 3 (browse + protocol templates)
- `.project/architecture-phase4.md` — Phase 4 (session preview + quality)
- [BLE-Protocol](BLE-Protocol.md)
- [Data-Format](Data-Format.md)
- [Time-Sync](Time-Sync.md)
