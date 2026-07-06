# WheelAthlete Wiki — Home

> **Version:** v0.1.0 (Data Collection MVP, pre-release)
> **Repo:** [NnopponS/WheelAthelse](https://github.com/NnopponS/WheelAthelse)
> **Languages:** [English](../README.md) · [ภาษาไทย](../README.th.md)

Welcome to the WheelAthlete wiki. This is the detailed reference for the
v0.1.0 release. For a quick start, read the [README](../README.md) first.

## Pages

| Page | What's inside |
|------|---------------|
| [Home](Home.md) | This page — index + release summary |
| [Architecture](Architecture.md) | System topology, component breakdown, data flow |
| [BLE-Protocol](BLE-Protocol.md) | GATT service, characteristics, packet layout, commands |
| [Data-Format](Data-Format.md) | CSV schema, meta.json, protocols.json, storage layout |
| [Time-Sync](Time-Sync.md) | Clock offset/drift estimation, scheduled start, beep marker |
| [Build-Guide](Build-Guide.md) | Firmware flash + Flutter app build, troubleshooting |
| [Field-Protocol](Field-Protocol.md) | Step-by-step data collection procedure |
| [Testing](Testing.md) | Test strategy, coverage, evidence reports |
| [Roadmap](Roadmap.md) | What's done in v0.1.0 + planned phases |
| [Changelog](Changelog.md) | Per-version change log |

## v0.1.0 at a glance

- **Firmware:** 0.2.0 (M5StickCPlus2, ESP32, NimBLE)
- **App:** 1.0.0+1 (Flutter, iOS + Android, Riverpod)
- **BLE Protocol:** 1.1.0
- **Status:** pre-release — data collection only, no ML yet

## Quick links

- [GitHub Release v0.1.0](https://github.com/NnopponS/WheelAthelse/releases/tag/v0.1.0)
- [BLE protocol spec (canonical)](../ble-protocol.md)
- [Field data collection protocol](../data-collection-protocol.md)
- [Architecture — Phase 1](../../.project/architecture.md)
- [Architecture — Phase 3](../../.project/architecture-phase3.md)
- [Architecture — Phase 4](../../.project/architecture-phase4.md)
