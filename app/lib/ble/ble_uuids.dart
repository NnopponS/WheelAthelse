/// WheelAthlete BLE UUIDs and packet-size constants.
///
/// Single source of truth on the app side for the GATT contract defined in
/// `docs/ble-protocol.md` §1 and §2. The firmware side mirrors these in
/// `firmware/src/ble_types.h` — both must stay in sync.
class BleUuids {
  const BleUuids._(); // coverage:ignore-line

  // ── GATT Service (§1) ───────────────────────────────────────────────────
  static const String service =
      '0000a1b2-0000-1000-8000-00805f9b34fb';

  // ── Characteristics (§1.1) ──────────────────────────────────────────────
  static const String imuData =
      '0000a1b3-0000-1000-8000-00805f9b34fb';
  static const String control =
      '0000a1b4-0000-1000-8000-00805f9b34fb';
  static const String sync =
      '0000a1b5-0000-1000-8000-00805f9b34fb';
  static const String info =
      '0000a1b6-0000-1000-8000-00805f9b34fb';

  // ── Packet sizes (§2.1, §4.1, §5) ───────────────────────────────────────
  static const int imuSampleSize = 20;
  static const int syncResponseSize = 12;
  static const int infoSize = 16;

  // ── MTU ─────────────────────────────────────────────────────────────────
  /// App requests MTU 247 on connect (protocol §1 note) so a single IMU
  /// notify can carry up to 12 samples.
  static const int defaultMtu = 247;
}
