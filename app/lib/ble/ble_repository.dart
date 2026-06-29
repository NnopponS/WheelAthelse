import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:wheelathlete/ble/ble_uuids.dart';
import 'package:wheelathlete/ble/board_config.dart';
import 'package:wheelathlete/ble/device_info.dart';

/// Coarse BLE link state for one device, mirrored from
/// `flutter_blue_plus`'s `BluetoothConnectionState` but kept plugin-agnostic
/// so the repository interface is testable without a real radio.
///
/// flutter_blue_plus 2.x only exposes `disconnected` and `connected`; the
/// intermediate `connecting`/`disconnecting` are surfaced via the fake
/// repository in tests and may be re-added if a future plugin version
/// reintroduces them.
enum BleConnectionState { disconnected, connecting, connected, disconnecting }

/// A device discovered during a scan.
class ScannedDevice {
  const ScannedDevice({required this.id, required this.name, required this.rssi});

  /// Platform remote id (stable across scans for the same physical device).
  final String id;

  /// Advertised name (e.g. "WheelAthlete-L"). May be empty.
  final String name;

  /// RSSI in dBm (negative).
  final int rssi;
}

/// A device that has been connected + had its Info characteristic read.
class ConnectedDevice {
  const ConnectedDevice({
    required this.id,
    required this.name,
    required this.info,
  });

  final String id;
  final String name;
  final DeviceInfo info;
}

/// Abstract BLE access for the WheelAthlete app.
///
/// The app talks to this interface; the real implementation
/// ([FlutterBluePlusBleRepository]) wraps `flutter_blue_plus`, and tests
/// inject [FakeBleRepository]. This keeps BLE I/O out of state logic so the
/// connection manager is fully unit-testable.
abstract class BleRepository {
  /// Live scan results stream. Emits the current cumulative list each time a
  /// new device is found. Completes when the scan stops.
  Stream<List<ScannedDevice>> get scanResults;

  /// Whether a scan is currently running.
  bool get isScanning;

  /// Start a scan for devices advertising the WheelAthlete service.
  /// Throws if a scan is already in progress.
  Future<void> startScan(Duration timeout);

  /// Stop an in-progress scan early.
  Future<void> stopScan();

  /// Connect to [deviceId], request MTU 247, discover services, and read the
  /// Info characteristic. Returns the parsed [ConnectedDevice].
  ///
  /// Throws if the device is not found or Info cannot be read.
  Future<ConnectedDevice> connect(String deviceId);

  /// Live connection-state stream for [deviceId].
  Stream<BleConnectionState> connectionState(String deviceId);

  /// Disconnect [deviceId] if connected. No-op if already disconnected.
  Future<void> disconnect(String deviceId);

  /// Read the current RSSI for a connected device (used to refresh the
  /// ConnectionCard signal strength). Throws if not connected.
  Future<int> readRssi(String deviceId);

  /// Live IMU Data characteristic notify stream for [deviceId] (§2).
  ///
  /// Each event is the raw bytes of one notify payload
  /// (`[uint8 count][sample_0]...[sample_{count-1}]`). The caller is
  /// responsible for parsing via [ImuPacketParser]. Throws if [deviceId] is
  /// not connected.
  Stream<List<int>> imuData(String deviceId);

  /// Live Sync characteristic notify stream for [deviceId] (§4).
  ///
  /// Each event is the raw bytes of one Sync notification
  /// (`[uint8 event_id][payload...]`). The caller parses via
  /// `SyncEvent.parse`. Throws if [deviceId] is not connected.
  Stream<List<int>> syncData(String deviceId);

  /// Writes [bytes] to the Control characteristic of [deviceId] (§3).
  ///
  /// The caller encodes the command via `ControlCommand.*`. Throws if
  /// [deviceId] is not connected or the write fails.
  Future<void> writeControl(String deviceId, List<int> bytes);

  /// Live Battery Level stream for [deviceId] (Battery Service 0x180F /
  /// 0x2A19). Emits the battery percentage (0–100) on each notification.
  /// Throws if [deviceId] is not connected.
  Stream<int> batteryLevel(String deviceId);

  /// Reads the Config characteristic (a1b7, 22 bytes) and returns a parsed
  /// [BoardConfig] with the current board name, wheel side, sample rate,
  /// and firmware version. Throws if [deviceId] is not connected.
  Future<BoardConfig> readConfig(String deviceId);
}

// ── flutter_blue_plus implementation ──────────────────────────────────────
// coverage:ignore-start
// This production adapter wraps flutter_blue_plus which requires real BLE
// hardware. It is a thin I/O translator with no branching logic — every
// method delegates directly to the plugin. The pure logic it calls
// (DeviceInfo.parse, WheelId.fromByte) is fully covered by unit tests, and
// the state machine that drives it (ConnectionManagerNotifier) is fully
// covered via FakeBleRepository. Field testing against real M5StickCPlus2
// hardware is subtask #10.

/// Production [BleRepository] backed by `flutter_blue_plus`.
///
/// Thin adapter: all parsing lives in [DeviceInfo]; all state lives in the
/// Riverpod notifier. This class only translates plugin types ↔ domain
/// types so it can be swapped out in tests.
class FlutterBluePlusBleRepository implements BleRepository {
  FlutterBluePlusBleRepository();

  final fbp.Guid _serviceGuid = fbp.Guid(BleUuids.service);
  final fbp.Guid _infoGuid = fbp.Guid(BleUuids.info);
  final fbp.Guid _imuGuid = fbp.Guid(BleUuids.imuData);
  final fbp.Guid _syncGuid = fbp.Guid(BleUuids.sync);
  final fbp.Guid _controlGuid = fbp.Guid(BleUuids.control);
  final fbp.Guid _batteryServiceGuid = fbp.Guid(BleUuids.batteryService);
  final fbp.Guid _batteryLevelGuid = fbp.Guid(BleUuids.batteryLevel);
  final fbp.Guid _configGuid = fbp.Guid(BleUuids.config);

  StreamSubscription<List<fbp.ScanResult>>? _scanSub;
  final StreamController<List<ScannedDevice>> _scanController =
      StreamController<List<ScannedDevice>>.broadcast();
  bool _scanning = false;

  @override
  Stream<List<ScannedDevice>> get scanResults => _scanController.stream;

  @override
  bool get isScanning => _scanning;

  @override
  Future<void> startScan(Duration timeout) async {
    if (_scanning) {
      throw StateError('BLE scan already in progress');
    }
    _scanning = true;
    _scanSub = fbp.FlutterBluePlus.onScanResults.listen(
      (results) => _scanController.add(
        results
            .where((r) =>
                r.advertisementData.serviceUuids.contains(_serviceGuid) ||
                r.advertisementData.advName.startsWith('WheelAthlete'))
            .map((r) => ScannedDevice(
                  id: r.device.remoteId.str,
                  name: r.advertisementData.advName.isNotEmpty
                      ? r.advertisementData.advName
                      : r.device.platformName,
                  rssi: r.rssi,
                ))
            .toList(growable: false),
      ),
      onError: _scanController.addError,
    );
    try {
      await fbp.FlutterBluePlus.startScan(
        withServices: [_serviceGuid],
        timeout: timeout,
      );
    } finally {
      await _scanSub?.cancel();
      _scanning = false;
    }
  }

  @override
  Future<void> stopScan() async {
    await fbp.FlutterBluePlus.stopScan();
    await _scanSub?.cancel();
    _scanning = false;
  }

  @override
  Future<ConnectedDevice> connect(String deviceId) async {
    final device = fbp.BluetoothDevice.fromId(deviceId);
    // WheelAthlete is a nonprofit / research project → nonprofit license.
    // `mtu` is auto-requested on Android; iOS negotiates automatically.
    await device.connect(
      license: fbp.License.nonprofit,
      mtu: BleUuids.defaultMtu,
      timeout: const Duration(seconds: 10),
    );
    final services = await device.discoverServices();
    final service = services.firstWhere((s) => s.serviceUuid == _serviceGuid);
    final infoChar = service.characteristics.firstWhere(
      (c) => c.characteristicUuid == _infoGuid,
    );
    final infoBytes = await infoChar.read();
    final info = DeviceInfo.parse(infoBytes);
    return ConnectedDevice(id: deviceId, name: device.platformName, info: info);
  }

  @override
  Stream<BleConnectionState> connectionState(String deviceId) {
    final device = fbp.BluetoothDevice.fromId(deviceId);
    return device.connectionState.map(_mapConnectionState);
  }

  @override
  Future<void> disconnect(String deviceId) async {
    final device = fbp.BluetoothDevice.fromId(deviceId);
    await device.disconnect();
  }

  @override
  Future<int> readRssi(String deviceId) async {
    final device = fbp.BluetoothDevice.fromId(deviceId);
    return device.readRssi();
  }

  @override
  Stream<List<int>> imuData(String deviceId) {
    // flutter_blue_plus 2.x removed servicesStream (deprecated → yields []).
    // Services discovered in connect() are cached on the device object, so we
    // resolve the IMU Data characteristic from servicesList and forward its
    // lastValueStream (notify). We use a broadcast controller so the caller
    // can listen multiple times; the underlying notify stream is already
    // broadcast.
    final controller = StreamController<List<int>>.broadcast();
    final device = fbp.BluetoothDevice.fromId(deviceId);
    () async {
      try {
        final services = device.servicesList;
        final service = services.firstWhere((s) => s.serviceUuid == _serviceGuid);
        final imuChar = service.characteristics
            .firstWhere((c) => c.characteristicUuid == _imuGuid);
        if (!imuChar.isNotifying) {
          await imuChar.setNotifyValue(true);
        }
        final sub = imuChar.lastValueStream.listen(
          (bytes) {
            // flutter_blue_plus emits an empty list on subscribe (before any
            // notify arrives) and can also deliver empty payloads on reconnect.
            // Filter them here so the parser never sees an empty batch.
            if (bytes.isEmpty) return;
            controller.add(bytes);
          },
          onError: controller.addError,
          onDone: controller.close,
        );
        controller.onCancel = () {
          sub.cancel();
          // Leave notify enabled — firmware keeps streaming until STOP cmd.
        };
      } on Object catch (e, st) {
        controller.addError(e, st);
        await controller.close();
      }
    }();
    return controller.stream;
  }

  @override
  Stream<List<int>> syncData(String deviceId) {
    // Same pattern as imuData: resolve the Sync characteristic from the
    // cached servicesList, enable notify, and forward lastValueStream.
    final controller = StreamController<List<int>>.broadcast();
    final device = fbp.BluetoothDevice.fromId(deviceId);
    () async {
      try {
        final services = device.servicesList;
        final service = services.firstWhere((s) => s.serviceUuid == _serviceGuid);
        final syncChar = service.characteristics
            .firstWhere((c) => c.characteristicUuid == _syncGuid);
        if (!syncChar.isNotifying) {
          await syncChar.setNotifyValue(true);
        }
        final sub = syncChar.lastValueStream.listen(
          (bytes) {
            if (bytes.isEmpty) return;
            controller.add(bytes);
          },
          onError: controller.addError,
          onDone: controller.close,
        );
        controller.onCancel = () => sub.cancel();
      } on Object catch (e, st) {
        controller.addError(e, st);
        await controller.close();
      }
    }();
    return controller.stream;
  }

  @override
  Future<void> writeControl(String deviceId, List<int> bytes) async {
    final device = fbp.BluetoothDevice.fromId(deviceId);
    final services = device.servicesList;
    final service = services.firstWhere((s) => s.serviceUuid == _serviceGuid);
    final controlChar = service.characteristics
        .firstWhere((c) => c.characteristicUuid == _controlGuid);
    await controlChar.write(bytes.toList(), withoutResponse: false);
  }

  @override
  Stream<int> batteryLevel(String deviceId) {
    // Resolve the Battery Service (0x180F) + Battery Level char (0x2A19)
    // from the cached servicesList, enable notify, and forward lastValueStream.
    final controller = StreamController<int>.broadcast();
    final device = fbp.BluetoothDevice.fromId(deviceId);
    () async {
      try {
        final services = device.servicesList;
        final batService = services.firstWhere(
          (s) => s.serviceUuid == _batteryServiceGuid,
        );
        final batChar = batService.characteristics
            .firstWhere((c) => c.characteristicUuid == _batteryLevelGuid);
        if (!batChar.isNotifying) {
          await batChar.setNotifyValue(true);
        }
        final sub = batChar.lastValueStream.listen(
          (bytes) {
            if (bytes.isEmpty) return;
            controller.add(bytes[0]);
          },
          onError: controller.addError,
          onDone: controller.close,
        );
        controller.onCancel = () => sub.cancel();
      } on Object catch (e, st) {
        controller.addError(e, st);
        await controller.close();
      }
    }();
    return controller.stream;
  }

  // flutter_blue_plus 2.x BluetoothConnectionState only has disconnected /
  // connected (the old connecting/disconnecting values were removed). We map
  // the two remaining values to our coarser enum.
  static BleConnectionState _mapConnectionState(fbp.BluetoothConnectionState s) =>
      switch (s) {
        fbp.BluetoothConnectionState.disconnected => BleConnectionState.disconnected,
        fbp.BluetoothConnectionState.connected => BleConnectionState.connected,
      };

  @override
  Future<BoardConfig> readConfig(String deviceId) async {
    final device = fbp.BluetoothDevice.fromId(deviceId);
    final services = device.servicesList;
    final service = services.firstWhere((s) => s.serviceUuid == _serviceGuid);
    final configChar = service.characteristics
        .firstWhere((c) => c.characteristicUuid == _configGuid);
    final bytes = await configChar.read();
    return BoardConfig.parse(bytes);
  }
}
// coverage:ignore-end

// ── Fake for tests ────────────────────────────────────────────────────────

/// Seed device for [FakeBleRepository].
class FakeDevice {
  const FakeDevice({required this.id, required this.name, required this.rssi});
  final String id;
  final String name;
  final int rssi;
}

/// In-memory [BleRepository] for unit/widget tests — no real radio needed.
///
/// Scan emits the seeded [devices] list once when [startScan] is awaited.
/// Connect looks up [infoFor] by id. Connection state is tracked in a map
/// and emitted through per-device broadcast streams.
class FakeBleRepository implements BleRepository {
  FakeBleRepository({
    required this.devices,
    this.infoFor = const {},
    this.configFor = const {},
  });

  final List<FakeDevice> devices;
  final Map<String, DeviceInfo> infoFor;

  /// Seeded Config char payloads (22 bytes) per device id. If a device is
  /// not in this map, `readConfig` throws.
  final Map<String, List<int>> configFor;

  final _scanController = StreamController<List<ScannedDevice>>.broadcast();
  final _states = <String, StreamController<BleConnectionState>>{};
  final _imuControllers = <String, StreamController<List<int>>>{};
  final _syncControllers = <String, StreamController<List<int>>>{};
  final _batteryControllers = <String, StreamController<int>>{};
  bool _scanning = false;

  @override
  Stream<List<ScannedDevice>> get scanResults => _scanController.stream;

  @override
  bool get isScanning => _scanning;

  @override
  Future<void> startScan(Duration timeout) async {
    if (_scanning) throw StateError('BLE scan already in progress');
    _scanning = true;
    // Emit synchronously-ish then mark done.
    _scanController.add(
      devices
          .map((d) => ScannedDevice(id: d.id, name: d.name, rssi: d.rssi))
          .toList(growable: false),
    );
    _scanning = false;
  }

  @override
  Future<void> stopScan() async {
    _scanning = false;
  }

  @override
  Future<ConnectedDevice> connect(String deviceId) async {
    final dev = devices.firstWhere(
      (d) => d.id == deviceId,
      orElse: () => throw StateError('No fake device with id $deviceId'),
    );
    final info = infoFor[deviceId];
    if (info == null) {
      throw StateError('No Info payload seeded for device $deviceId');
    }
    _stateController(deviceId).add(BleConnectionState.connecting);
    _stateController(deviceId).add(BleConnectionState.connected);
    return ConnectedDevice(id: deviceId, name: dev.name, info: info);
  }

  @override
  Stream<BleConnectionState> connectionState(String deviceId) =>
      _stateController(deviceId).stream;

  @override
  Future<void> disconnect(String deviceId) async {
    final c = _states[deviceId];
    if (c != null && !c.isClosed) {
      c.add(BleConnectionState.disconnecting);
      c.add(BleConnectionState.disconnected);
    }
  }

  @override
  Future<int> readRssi(String deviceId) async {
    final dev = devices.firstWhere((d) => d.id == deviceId);
    return dev.rssi;
  }

  @override
  Stream<List<int>> imuData(String deviceId) => _imuController(deviceId).stream;

  /// Exposes the IMU notify stream controller for a device so tests can
  /// inject raw batch bytes. The controller is `sync: true` so events are
  /// delivered immediately to listeners (no microtask race with test expects).
  StreamController<List<int>>? imuController(String deviceId) =>
      _imuControllers[deviceId];

  @override
  Stream<List<int>> syncData(String deviceId) => _syncController(deviceId).stream;

  /// Exposes the Sync notify stream controller for a device so tests can
  /// inject raw Sync event bytes. Same `sync: true` contract as
  /// [imuController].
  StreamController<List<int>>? syncController(String deviceId) =>
      _syncControllers[deviceId];

  @override
  Stream<int> batteryLevel(String deviceId) =>
      _batteryController(deviceId).stream;

  /// Exposes the Battery Level notify stream controller for a device so tests
  /// can inject battery percentage values. `sync: true` for immediate delivery.
  StreamController<int>? batteryController(String deviceId) =>
      _batteryControllers[deviceId];

  @override
  Future<BoardConfig> readConfig(String deviceId) async {
    final bytes = configFor[deviceId];
    if (bytes == null) {
      throw StateError('No Config payload seeded for device $deviceId');
    }
    return BoardConfig.parse(bytes);
  }

  /// Records the last Control command written for [deviceId] (or null if
  /// none). Tests inspect this to verify the app sent the right bytes.
  List<int>? lastControlWrite(String deviceId) => _lastControlWrites[deviceId];

  @override
  Future<void> writeControl(String deviceId, List<int> bytes) async {
    _lastControlWrites[deviceId] = bytes;
  }

  final Map<String, List<int>> _lastControlWrites = {};

  StreamController<List<int>> _imuController(String deviceId) =>
      _imuControllers.putIfAbsent(
        deviceId,
        () => StreamController<List<int>>.broadcast(sync: true),
      );

  StreamController<List<int>> _syncController(String deviceId) =>
      _syncControllers.putIfAbsent(
        deviceId,
        () => StreamController<List<int>>.broadcast(sync: true),
      );

  StreamController<int> _batteryController(String deviceId) =>
      _batteryControllers.putIfAbsent(
        deviceId,
        () => StreamController<int>.broadcast(sync: true),
      );

  StreamController<BleConnectionState> _stateController(String deviceId) =>
      _states.putIfAbsent(
        deviceId,
        // sync: true so events are delivered immediately to listeners in
        // tests (no microtask scheduling race with the test's expects).
        () => StreamController<BleConnectionState>.broadcast(sync: true),
      );
}
