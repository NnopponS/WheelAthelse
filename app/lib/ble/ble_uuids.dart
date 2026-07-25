/// WheelAthlete BLE UUIDs and packet-size constants.
///
/// Single source of truth on the app side for the GATT contract defined in
/// `docs/ble-protocol.md` §1 and §2. The firmware side mirrors these in
/// `firmware/src/ble_types.h` — both must stay in sync.
class BleUuids {
  const BleUuids._(); // coverage:ignore-line

  // ── GATT Service (§1) ───────────────────────────────────────────────────
  static const String service = '0000a1b2-0000-1000-8000-00805f9b34fb';

  // ── Characteristics (§1.1) ──────────────────────────────────────────────
  static const String imuData = '0000a1b3-0000-1000-8000-00805f9b34fb';
  static const String control = '0000a1b4-0000-1000-8000-00805f9b34fb';
  static const String sync = '0000a1b5-0000-1000-8000-00805f9b34fb';
  static const String info = '0000a1b6-0000-1000-8000-00805f9b34fb';
  // ── Config read characteristic (Phase 2 §1.2) ───────────────────────────
  /// Config characteristic UUID (a1b7) — Read, 22 bytes.
  /// Layout: [name 16B][wheel_id 1B][rate_hz 2B LE][fw_major 1B][fw_minor 1B][fw_patch 1B]
  static const String config = '0000a1b7-0000-1000-8000-00805f9b34fb';

  // ── Standard Battery Service (Phase 2 §1) ───────────────────────────────
  /// Standard BLE Battery Service UUID (0x180F).
  static const String batteryService = '0000180f-0000-1000-8000-00805f9b34fb';

  /// Battery Level characteristic UUID (0x2A19) — Notify, uint8 0-100.
  static const String batteryLevel = '00002a19-0000-1000-8000-00805f9b34fb';

  // ── Packet sizes (§2.1, §4.1, §5, §1.2) ─────────────────────────────────
  static const int imuSampleSize = 20;
  static const int syncResponseSize = 12;
  static const int infoSize = 16;
  static const int configSize = 31;

  // ── MTU ─────────────────────────────────────────────────────────────────
  /// App requests MTU 247 on connect (protocol §1 note) so a single IMU
  /// notify can carry up to 12 samples.
  static const int defaultMtu = 247;
}
