# Data Format

> v0.1.0 — Data Collection MVP

## Storage layout

Sessions are stored on-device under the app documents directory:

```
<app documents>/
└── WheelAthleteData/
    ├── <topic>/
    │   ├── topic_meta.json
    │   └── trial_<NN>/
    │       ├── session_<id>.csv
    │       └── session_<id>_meta.json
    └── protocols.json
```

- `<topic>` — user-defined topic name (e.g. `sprint_test`, `athlete_A`)
- `trial_<NN>` — zero-padded trial number, auto-incremented per topic
- `session_<id>` — timestamp-based unique session ID

## `session_<id>.csv`

CSV with **separate Left and Right tables** (Phase 3 change — earlier
versions had a single combined table).

### Columns

| Column | Type | Meaning |
|--------|------|---------|
| `seq` | uint32 | Sample sequence from firmware (detects packet loss) |
| `wheel` | char | `L` or `R` |
| `timestamp_app_ms` | uint64 | Phone epoch ms when sample received (has BLE jitter) |
| `timestamp_device_us` | uint32 | `micros()` on M5 when sampled |
| `timestamp_synced_ms` | uint64 | **UTC epoch ms after offset/drift correction** — primary key for cross-wheel + camera alignment |
| `ax, ay, az` | float | Acceleration in g (raw × `accel_scale` from Info) |
| `gx, gy, gz` | float | Gyro in dps (raw × `gyro_scale` from Info) |
| `marker` | 0/1 | 1 = Mark Event pressed (legacy; always 0 in v0.1.0) |

### Which timestamp to use?

| Use case | Column |
|----------|--------|
| Cross-wheel alignment | `timestamp_synced_ms` |
| Camera alignment | `timestamp_synced_ms` (via beep 3-2-1) |
| Detect packet loss | `seq` (gaps = dropped samples) |
| Measure true sample interval | `timestamp_device_us` (per wheel) |
| Debug BLE latency | `timestamp_app_ms - timestamp_synced_ms` |

**`timestamp_synced_ms` is the primary key for all downstream analysis.**

## `session_<id>_meta.json`

```json
{
  "sessionId": "20260629_153012_L",
  "topic": "sprint_test",
  "trialNumber": 1,
  "athlete": "Athlete A",
  "datetime": "2026-06-29T15:30:12Z",
  "sampleRateHz": 100,
  "durationMs": 30000,
  "sampleCount": 6000,
  "dropCount": 0,
  "syncQuality": {
    "left": {
      "offsetUs": 12345,
      "driftPpm": 1.2,
      "driftResidualRmsMs": 0.8
    },
    "right": {
      "offsetUs": 9876,
      "driftPpm": 0.9,
      "driftResidualRmsMs": 1.1
    }
  },
  "notes": "First sprint trial",
  "cameraVideoFilename": "sprint_test_trial_01.mp4",
  "tags": ["baseline", "indoor"],
  "protocolTemplateId": "uuid-or-hex-timestamp"
}
```

### Sync quality fields
- `offsetUs` — estimated clock offset (microseconds) at sync time
- `driftPpm` — estimated drift rate (parts per million)
- `driftResidualRmsMs` — RMS residual after drift correction (milliseconds)
  - `< 2 ms` → good (green badge)
  - `2–5 ms` → fair (amber badge)
  - `> 5 ms` → poor (red badge)
  - `null`  → unknown (grey badge)

### Tags
- Free-form string list, editable from Browse → session → tag editor
- Used for search/filter on Browse
- Default: `[]` for new sessions

### `protocolTemplateId`
- Links session to a protocol template (optional)
- Used by the Experiment Tracker dashboard to count trials per template

## `topic_meta.json`

```json
{
  "topic": "sprint_test",
  "createdAt": "2026-06-29T15:00:00Z",
  "notes": "20m sprint test series"
}
```

## `protocols.json`

Single file storing all protocol templates:

```json
[
  {
    "id": "20260629_150000",
    "name": "20m Sprint Test",
    "description": "From standing start, 20m max effort",
    "topicName": "sprint_test",
    "targetTrialCount": 5,
    "sampleRateHz": 100,
    "createdAt": "2026-06-29T15:00:00Z"
  }
]
```

### Fields
- `id` — UUID or hex timestamp (unique)
- `name` — display name (e.g. "20m Sprint Test")
- `description` — optional human-readable description
- `topicName` — auto-created/linked topic folder name
- `targetTrialCount` — for progress bar ("3/5 trials done")
- `sampleRateHz` — default 100
- `createdAt` — ISO 8601 timestamp

## Excel export (.xlsx)

The Excel exporter produces a workbook with:
- Separate sheets for Left and Right wheel data
- Same columns as the CSV
- Header row with column names

## Backward compatibility

- Sessions recorded before tags existed default to `tags: []`
- Sessions recorded before `protocolTemplateId` existed default to `null`
- The `marker` column is preserved for reading legacy sessions but is
  always `0` for new recordings (Mark Event was removed in Phase 3)
