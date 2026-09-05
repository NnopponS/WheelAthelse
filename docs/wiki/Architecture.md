# Architecture

Current release line: `v1.8.0`.

## Two supported operator clients

```text
Left/Right WheelAthlete sensors
(M5StickCPlus2 or XIAO BLE Sense)
              │
            BLE GATT
              │
      ┌───────┴────────┐
      │                │
      ▼                ▼
Flutter Mobile     Python Windows
 iOS/Android        PySide6 GUI
 direct BLE             │
      │            localhost IPC
      │                 │
      │          Acquisition daemon
      │          Bleak / WinRT BLE
      ▼                 ▼
CSV/meta data       .waj journal
                   QC + recovery
```

Use one operator client at a time with a sensor pair.

## Firmware

Maintained targets:

- `M5plus2_firmware/`
- `Xiao_firmware/`

They share the BLE protocol semantics, left/right identity model, 50/100/200 Hz configuration, synchronized lifecycle, sequence accounting, replay/recovery support, and acquisition-health telemetry.

## Mobile

The Flutter mobile app owns BLE directly. Its state/domain layers handle connection, synchronization, recording, storage, preview, experiment metadata, QC, and export. Supported runtime targets are Android and iOS only.

## Windows

The Python Windows app deliberately separates UI from authoritative acquisition:

```text
Bleak notification
 -> strict parser / sequence accounting
 -> sync mapping
 -> append-only .waj
 -> final QC / recovery
 -> bounded localhost preview/status
 -> PySide6 GUI
```

Raw research samples are not routed through Qt charts. A slow/frozen GUI therefore cannot silently become the authoritative raw-data bottleneck.

## Storage

- Mobile: app-document topic/trial/session storage plus export artifacts.
- Windows: append-only `.waj` is authoritative; CSV is derived and incomplete journals are recoverable.

## Canonical references

- `.project/architecture.md`
- `docs/ble-protocol.md`
- `tools/pc_gui/README.md`
- `packaging/windows/README.md`
