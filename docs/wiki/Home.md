# WheelAthlete Wiki — Home

> **Current release line:** v1.8.0
> **Products:** Flutter Mobile (iOS/Android) + Python Windows (PySide6)
> **Repo:** [NnopponS/WheelAthelse](https://github.com/NnopponS/WheelAthelse)

WheelAthlete is a synchronized dual-wheel IMU acquisition platform for wheelchair sports research. The current source tree has two operator applications only: the Flutter mobile app and the Python Windows Research Edition.

## Versions

- Product / Windows package: `1.8.0`
- Flutter mobile: `1.8.0+9`
- M5StickCPlus2 firmware: `1.8.0`
- XIAO firmware: `1.8.0`
- BLE protocol: `1.8.0`

## Pages

- [Architecture](Architecture.md) — current two-client architecture
- [BLE Protocol](BLE-Protocol.md) — protocol reference; canonical spec is `../ble-protocol.md`
- [Data Format](Data-Format.md) — research data formats
- [Time Sync](Time-Sync.md) — synchronization model
- [Build Guide](Build-Guide.md) — mobile, firmware, and Windows packaging
- [Field Protocol](Field-Protocol.md) — field collection procedure
- [Testing](Testing.md) — verification strategy
- [Roadmap](Roadmap.md) — current and planned work
- [Changelog](Changelog.md) — release history

## Current architecture references

- [Root README](../../README.md)
- [Python Windows app](../../tools/pc_gui/README.md)
- [Windows packaging](../../packaging/windows/README.md)
- [Canonical project state](../../.project/README.md)
- [Canonical BLE protocol](../ble-protocol.md)

Flutter Windows, Flutter Web, and the legacy Tkinter desktop GUI are retired and removed; use Git history if their old implementation is needed for comparison.
