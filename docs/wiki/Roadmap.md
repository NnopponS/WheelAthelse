# Roadmap

## Current — v1.8.0

### Flutter mobile

- Android + iOS only
- dual-wheel BLE connection and realtime preview
- synchronized recording and timestamp mapping
- topic/trial/session organization
- templates, experiment tracking, tags, search/filter
- session preview, QC/statistics, CSV/Excel/ZIP export

### Python Windows

- PySide6 operator UI
- separate Bleak/WinRT acquisition daemon
- append-only `.waj` authoritative recording
- sequence/loss/queue/sync diagnostics
- crash recovery and derived CSV export
- portable PyInstaller package + Inno Setup installer

### Firmware

- M5StickCPlus2 and XIAO nRF52840 Sense targets
- coordinated 1.8.0 BLE/lifecycle contract
- 50/100/200 Hz, synchronized start/stop, range configuration
- replay/recovery and acquisition-health telemetry

## Current hardware validation gate

Software tests and long-run simulations exist, but real two-XIAO RF throughput, distance behavior, and physical left/right start skew remain gated by the physical acceptance matrix. Do not convert simulated results into hardware claims.

## Planned

- execute and record the physical two-XIAO acceptance matrix;
- continue dataset/biomechanics model research without coupling it to the acquisition UI;
- improve automated release/CI checks;
- automated video↔IMU alignment where research needs it;
- optional future OTA/multi-wheel work only after the current two-wheel acquisition path remains stable.

## Release history

| Version | Date | Summary |
|---|---|---|
| `v1.8.0` | 2026-09-05 | Product consolidation: Flutter mobile + Python Windows, packaging cleanup, coordinated 1.8.0 metadata |
| `v1.7.0` | 2026-07-25 | Stable dual-wheel reliability release: mobile 1.7.0+8, firmware/BLE 1.7.0 |
| `v0.1.0` | 2026-07-06 | First usable data-collection MVP |

The v1.8.0 line is being developed on `codex/pc-version`; it is not a statement that `main` has been updated or that a GitHub release/tag has already been created.
