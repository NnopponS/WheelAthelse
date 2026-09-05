# Data Format

Current release line: `v1.8.0`.

WheelAthlete has platform-appropriate authoritative storage while keeping the same sensor/protocol semantics.

## Mobile sessions

The Flutter app stores sessions under its app documents directory:

```text
WheelAthleteData/
└── <topic>/
    └── trial_<NN>/
        ├── session_<id>.csv
        └── session_<id>_meta.json
```

Protocol templates are stored alongside the mobile data root.

Important mobile CSV fields include:

- `seq` — device sample sequence for gap detection;
- `wheel` — `L` or `R`;
- `timestamp_app_ms` — client receive time;
- `timestamp_device_us` — device clock;
- `timestamp_synced_ms` — synchronized UTC/client timeline used for alignment;
- `ax, ay, az` — acceleration;
- `gx, gy, gz` — angular velocity;
- `marker` — legacy compatibility column; current recordings do not expose Mark Event in the UI.

Metadata carries recording configuration, versions, quality/synchronization information, notes/tags, and experiment/protocol identity where applicable.

## Windows sessions

The Python acquisition daemon uses an append-only `.waj` journal as the **authoritative research record**.

```text
~/Documents/WheelAthlete/PC Sessions/
  <session>.waj       # finalized authoritative journal
  <session>.open      # incomplete/recoverable journal while recording/crashed
  ...derived CSV/QC artifacts...
```

Windows CSV is derived from the journal; it is not the primary write path. Final QC compares acquisition/journal counts and preserves diagnostics needed to identify loss or failure.

## Storage rule

Do not infer authoritative sample completeness from UI preview values. Mobile recording buffers/storage and the Windows `.waj` path are the data sources of record for their respective clients.

See `docs/ble-protocol.md` for the wire format and `tools/pc_gui/README.md` for Windows session behavior.
