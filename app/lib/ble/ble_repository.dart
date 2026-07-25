import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
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
  const ScannedDevice({
    required this.id,
    required this.name,
    required this.rssi,
  });

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

/// One owned BLE notification subscription.
///
/// The native listener is attached before notifications are enabled. [ready]
/// completes only after the CCCD write succeeds, allowing command writers to
/// wait without losing an immediate response. [close] releases the owner.
class BleNotificationChannel<T> {
  const BleNotificationChannel({
    required this.stream,
    required this.ready,
    required this.close,
  });

  final Stream<T> stream;
  final Future<void> ready;
  final Future<void> Function() close;
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

  /// Reasserts the platform's high-throughput BLE connection mode immediately
  /// before a recording. Platforms without configurable priority may no-op.
  Future<void> prepareForStreaming(String deviceId) async {}

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

  BleNotificationChannel<List<int>> imuNotifications(String deviceId) =>
      BleNotificationChannel<List<int>>(
        stream: imuData(deviceId),
        ready: Future<void>.value(),
        close: () async {},
      );

  /// Live Sync characteristic notify stream for [deviceId] (§4).
  ///
  /// Each event is the raw bytes of one Sync notification
  /// (`[uint8 event_id][payload...]`). The caller parses via
  /// `SyncEvent.parse`. Throws if [deviceId] is not connected.
  Stream<List<int>> syncData(String deviceId);

  BleNotificationChannel<List<int>> syncNotifications(String deviceId) =>
      BleNotificationChannel<List<int>>(
        stream: syncData(deviceId),
        ready: Future<void>.value(),
        close: () async {},
      );

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
  final _imuChannels = <String, BleNotificationChannel<List<int>>>{};
  final _syncChannels = <String, BleNotificationChannel<List<int>>>{};
  final _batteryStreams = <String, Stream<int>>{};
  Future<void> _gattTail = Future<void>.value();

  // Samsung's Android BLE host can return status 17 when two BluetoothGatt
  // instances issue operations in the same scheduling window. One global
  // queue plus a short quiet period keeps dual-board CCCD/control operations
  // away from that resource boundary. Scheduled recording START remains
  // aligned because each board receives an absolute device target time.
  static const _gattInterOperationDelay = Duration(milliseconds: 50);

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
    _scanSub = fbp.FlutterBluePlus.scanResults.listen(
      (results) => _scanController.add(_mapScanResults(results)),
      onError: _scanController.addError,
    );
    try {
      await fbp.FlutterBluePlus.startScan(timeout: timeout);
      // startScan() only starts the native scan; it does not await its timeout.
      // Keep our result subscription alive until FlutterBluePlus reports the
      // timer-driven stop, otherwise Samsung advertisements race a listener
      // that is cancelled immediately after the platform method returns.
      await fbp.FlutterBluePlus.isScanning
          .where((isScanning) => !isScanning)
          .first
          .timeout(
            timeout + const Duration(seconds: 2),
            onTimeout: () async {
              await fbp.FlutterBluePlus.stopScan();
              return false;
            },
          );
      // Samsung can deliver native advertisements while the Dart event
      // listener is briefly busy rebuilding the high-density Connect page.
      // flutter_blue_plus retains the cumulative snapshot for this scan, so
      // publish it once more before returning instead of losing a board until
      // the user scans again.
      final finalResults = _mapScanResults(fbp.FlutterBluePlus.lastScanResults);
      if (finalResults.isNotEmpty) _scanController.add(finalResults);
    } finally {
      await _scanSub?.cancel();
      _scanning = false;
    }
  }

  List<ScannedDevice> _mapScanResults(Iterable<fbp.ScanResult> results) =>
      results
          .where((result) {
            final advertisedName = result.advertisementData.advName;
            final platformName = result.device.platformName;
            return advertisedName.startsWith('WheelAthlete') ||
                platformName.startsWith('WheelAthlete') ||
                result.advertisementData.serviceUuids.contains(_serviceGuid);
          })
          .map(
            (result) => ScannedDevice(
              id: result.device.remoteId.str,
              name: result.advertisementData.advName.isNotEmpty
                  ? result.advertisementData.advName
                  : result.device.platformName,
              rssi: result.rssi,
            ),
          )
          .toList(growable: false);

  @override
  Future<void> stopScan() async {
    await fbp.FlutterBluePlus.stopScan();
    await _scanSub?.cancel();
    _scanning = false;
  }

  @override
  Future<ConnectedDevice> connect(String deviceId) async {
    // A previous Android connection may have ended without closing the global
    // flutter_blue_plus event stream. Never reuse its completed `ready`
    // future or stale CCCD state for a new physical connection.
    await _invalidateNotificationChannels(deviceId);
    final device = fbp.BluetoothDevice.fromId(deviceId);
    // WheelAthlete is a nonprofit / research project → nonprofit license.
    // `mtu` is auto-requested on Android; iOS negotiates automatically.
    await device.connect(
      license: fbp.License.nonprofit,
      mtu: BleUuids.defaultMtu,
      timeout: const Duration(seconds: 10),
    );

    // Request HIGH connection priority on Android. This is critical for
    // multi-connection streaming: without it, Android's BLE stack often
    // assigns the second connected device a slow default connection interval
    // (~100ms), which cannot keep up with 100 Hz IMU notifications and causes
    // massive packet drops on the second board. HIGH priority requests a
    // fast interval (7.5–15ms) for both devices so notifications flow
    // reliably. No-op on iOS (iOS manages this automatically).
    await prepareForStreaming(deviceId);

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
    return device.connectionState.map((nativeState) {
      final mapped = _mapConnectionState(nativeState);
      if (mapped == BleConnectionState.disconnected) {
        unawaited(_invalidateNotificationChannels(deviceId));
      }
      return mapped;
    });
  }

  @override
  Future<void> disconnect(String deviceId) async {
    await _invalidateNotificationChannels(deviceId);
    _batteryStreams.remove(deviceId);
    final device = fbp.BluetoothDevice.fromId(deviceId);
    await device.disconnect();
  }

  @override
  Future<void> prepareForStreaming(String deviceId) async {
    if (kIsWeb || !Platform.isAndroid) return;
    await _serializeGatt(deviceId, () async {
      final device = fbp.BluetoothDevice.fromId(deviceId);

      // Re-assert the negotiated MTU immediately before acquisition. Android
      // can leave the second peripheral at the 23-byte default even when the
      // connect-time auto request was accepted. At that MTU the firmware can
      // fit only one 20-byte sample in each notification, which is not enough
      // headroom for reliable dual-wheel 100 Hz streaming.
      var negotiatedMtu = device.mtuNow;
      try {
        negotiatedMtu = await device.requestMtu(
          BleUuids.defaultMtu,
          predelay: 0.0,
        );
      } on Object {
        negotiatedMtu = device.mtuNow;
      }
      const minimumStreamingMtu = 185;
      if (negotiatedMtu < minimumStreamingMtu) {
        throw StateError(
          'BLE MTU $negotiatedMtu is too small for reliable streaming '
          '(minimum $minimumStreamingMtu). Reconnect this wheel and retry.',
        );
      }

      try {
        await device.requestConnectionPriority(
          connectionPriorityRequest: fbp.ConnectionPriority.high,
        );
      } on Object {
        // The peripheral also requests a fast interval and notification
        // pacing remains safe when Android declines this best-effort request.
      }
    });
  }

  Future<void> _invalidateNotificationChannels(String deviceId) async {
    final channels = <BleNotificationChannel<List<int>>>[
      ?_imuChannels.remove(deviceId),
      ?_syncChannels.remove(deviceId),
    ];
    await Future.wait(channels.map((channel) => channel.close()));
  }

  @override
  Future<int> readRssi(String deviceId) async {
    final device = fbp.BluetoothDevice.fromId(deviceId);
    return device.readRssi();
  }

  @override
  Stream<List<int>> imuData(String deviceId) =>
      imuNotifications(deviceId).stream;

  @override
  BleNotificationChannel<List<int>> imuNotifications(String deviceId) =>
      _imuChannels.putIfAbsent(
        deviceId,
        () => _createNotificationChannel(
          deviceId: deviceId,
          characteristicGuid: _imuGuid,
          forceNotifyReset: true,
          onClosed: () => _imuChannels.remove(deviceId),
        ),
      );

  BleNotificationChannel<List<int>> _createNotificationChannel({
    required String deviceId,
    required fbp.Guid characteristicGuid,
    bool forceNotifyReset = false,
    required void Function() onClosed,
  }) {
    // Keep the native BLE callback short. With `sync: true`, one Android
    // notification could synchronously run parsing, recording, presentation,
    // and every downstream listener before flutter_blue_plus was allowed to
    // deliver the other wheel. An asynchronous controller gives each wheel a
    // fair event-queue turn and prevents UI work from blocking GATT callbacks.
    final controller = StreamController<List<int>>.broadcast();
    final ready = Completer<void>();
    final device = fbp.BluetoothDevice.fromId(deviceId);
    StreamSubscription<List<int>>? subscription;
    var closed = false;

    Future<void> close() async {
      if (closed) return;
      closed = true;
      onClosed();
      await subscription?.cancel();
      if (!controller.isClosed) await controller.close();
    }

    unawaited(() async {
      try {
        await _serializeGatt(deviceId, () async {
          final service = device.servicesList.firstWhere(
            (s) => s.serviceUuid == _serviceGuid,
          );
          final characteristic = service.characteristics.firstWhere(
            (c) => c.characteristicUuid == characteristicGuid,
          );
          // Notifications must never replay the characteristic's cached last
          // value. Firmware resets IMU sequence numbers on every START; a
          // cached batch from the previous Live/Record session would seed the
          // recovery buffer with the old sequence and make every fresh sample
          // (starting again at zero) look stale. onValueReceived forwards only
          // new native notifications and also prevents stale START/STOP ACKs
          // from completing a new lifecycle operation.
          subscription = characteristic.onValueReceived.listen(
            (bytes) {
              if (!closed && bytes.isNotEmpty) controller.add(bytes);
            },
            onError: (Object error, StackTrace stackTrace) {
              if (!closed) controller.addError(error, stackTrace);
            },
            onDone: close,
          );
          // Android may retain a locally cached `isNotifying=true` after a
          // failed/reconnected session even though the peripheral CCCD has
          // reset. IMU is quiescent while arming, so force a clean false/true
          // CCCD handshake before START. Sync stays continuously subscribed.
          if (forceNotifyReset && characteristic.isNotifying) {
            await characteristic.setNotifyValue(false);
          }
          if (!characteristic.isNotifying) {
            await characteristic.setNotifyValue(true);
          }
          if (!characteristic.isNotifying) {
            throw StateError('BLE notification setup was not acknowledged');
          }
        });
        if (!ready.isCompleted) ready.complete();
      } on Object catch (error, stackTrace) {
        if (!ready.isCompleted) ready.completeError(error, stackTrace);
        if (!closed) controller.addError(error, stackTrace);
        await close();
      }
    }());

    return BleNotificationChannel<List<int>>(
      stream: controller.stream,
      ready: ready.future,
      close: close,
    );
  }

  @override
  Stream<List<int>> syncData(String deviceId) =>
      syncNotifications(deviceId).stream;

  @override
  BleNotificationChannel<List<int>> syncNotifications(String deviceId) =>
      _syncChannels.putIfAbsent(
        deviceId,
        () => _createNotificationChannel(
          deviceId: deviceId,
          characteristicGuid: _syncGuid,
          onClosed: () => _syncChannels.remove(deviceId),
        ),
      );

  @override
  Future<void> writeControl(String deviceId, List<int> bytes) async {
    await _serializeGatt(deviceId, () async {
      final device = fbp.BluetoothDevice.fromId(deviceId);
      final services = device.servicesList;
      final service = services.firstWhere((s) => s.serviceUuid == _serviceGuid);
      final controlChar = service.characteristics.firstWhere(
        (c) => c.characteristicUuid == _controlGuid,
      );
      await controlChar.write(bytes.toList(), withoutResponse: false);
    });
  }

  Future<T> _serializeGatt<T>(
    String deviceId,
    Future<T> Function() operation,
  ) async {
    assert(deviceId.isNotEmpty);
    final previous = _gattTail;
    final released = Completer<void>();
    _gattTail = released.future;
    try {
      await previous;
      return await operation();
    } finally {
      await Future<void>.delayed(_gattInterOperationDelay);
      released.complete();
    }
  }

  @override
  Stream<int> batteryLevel(String deviceId) => _batteryStreams.putIfAbsent(
    deviceId,
    () => _createBatteryLevel(deviceId),
  );

  Stream<int> _createBatteryLevel(String deviceId) {
    // Resolve the Battery Service (0x180F) + Battery Level char (0x2A19)
    // from the cached servicesList, enable notify, and forward lastValueStream.
    final controller = StreamController<int>.broadcast();
    final device = fbp.BluetoothDevice.fromId(deviceId);
    () async {
      try {
        await _serializeGatt(deviceId, () async {
          final services = device.servicesList;
          final batService = services.firstWhere(
            (s) => s.serviceUuid == _batteryServiceGuid,
          );
          final batChar = batService.characteristics.firstWhere(
            (c) => c.characteristicUuid == _batteryLevelGuid,
          );
          final sub = batChar.lastValueStream.listen(
            (bytes) {
              if (bytes.isEmpty) return;
              controller.add(bytes[0]);
            },
            onError: controller.addError,
            onDone: controller.close,
          );
          if (!batChar.isNotifying) {
            await batChar.setNotifyValue(true);
          }
          // Notifications only report changes. Always read once after the
          // listener is attached so a stable battery value appears on connect.
          final initial = await batChar.read();
          if (initial.isNotEmpty) controller.add(initial[0]);
          controller.onCancel = () {
            _batteryStreams.remove(deviceId);
            sub.cancel();
          };
        });
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
  static BleConnectionState _mapConnectionState(
    fbp.BluetoothConnectionState s,
  ) => switch (s) {
    fbp.BluetoothConnectionState.disconnected =>
      BleConnectionState.disconnected,
    fbp.BluetoothConnectionState.connected => BleConnectionState.connected,
  };

  @override
  Future<BoardConfig> readConfig(String deviceId) async {
    final device = fbp.BluetoothDevice.fromId(deviceId);
    final services = device.servicesList;
    final service = services.firstWhere((s) => s.serviceUuid == _serviceGuid);
    final configChar = service.characteristics.firstWhere(
      (c) => c.characteristicUuid == _configGuid,
    );
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
    this.autoAcknowledgeControls = false,
    this.initialBatteryFor = const {},
    this.notificationReadyDelay = Duration.zero,
    Map<String, int> stopWriteFailuresFor = const {},
  }) : _remainingStopWriteFailures = Map.of(stopWriteFailuresFor);

  final List<FakeDevice> devices;
  final Map<String, DeviceInfo> infoFor;

  /// Seeded Config char payloads (22 bytes) per device id. If a device is
  /// not in this map, `readConfig` throws.
  final Map<String, List<int>> configFor;
  final bool autoAcknowledgeControls;
  final Map<String, int> initialBatteryFor;
  final Duration notificationReadyDelay;
  final Map<String, int> _remainingStopWriteFailures;

  final _scanController = StreamController<List<ScannedDevice>>.broadcast();
  final _states = <String, StreamController<BleConnectionState>>{};
  final _imuControllers = <String, StreamController<List<int>>>{};
  final _syncControllers = <String, StreamController<List<int>>>{};
  final _batteryControllers = <String, StreamController<int>>{};
  bool _scanning = false;
  final List<String> streamPreparationCalls = [];

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
    _disconnectCounts.update(deviceId, (count) => count + 1, ifAbsent: () => 1);
    final c = _states[deviceId];
    if (c != null && !c.isClosed) {
      c.add(BleConnectionState.disconnecting);
      c.add(BleConnectionState.disconnected);
    }
  }

  @override
  Future<void> prepareForStreaming(String deviceId) async {
    streamPreparationCalls.add(deviceId);
  }

  @override
  Future<int> readRssi(String deviceId) async {
    final dev = devices.firstWhere((d) => d.id == deviceId);
    return dev.rssi;
  }

  @override
  Stream<List<int>> imuData(String deviceId) => _imuController(deviceId).stream;

  @override
  BleNotificationChannel<List<int>> imuNotifications(String deviceId) =>
      BleNotificationChannel<List<int>>(
        stream: _imuController(deviceId).stream,
        ready: Future<void>.delayed(notificationReadyDelay),
        close: () async {},
      );

  /// Exposes the IMU notify stream controller for a device so tests can
  /// inject raw batch bytes. The controller is `sync: true` so events are
  /// delivered immediately to listeners (no microtask race with test expects).
  StreamController<List<int>>? imuController(String deviceId) =>
      _imuControllers[deviceId];

  @override
  Stream<List<int>> syncData(String deviceId) =>
      _syncController(deviceId).stream;

  @override
  BleNotificationChannel<List<int>> syncNotifications(String deviceId) =>
      BleNotificationChannel<List<int>>(
        stream: _syncController(deviceId).stream,
        ready: Future<void>.delayed(notificationReadyDelay),
        close: () async {},
      );

  /// Exposes the Sync notify stream controller for a device so tests can
  /// inject raw Sync event bytes. Same `sync: true` contract as
  /// [imuController].
  StreamController<List<int>>? syncController(String deviceId) =>
      _syncControllers[deviceId];

  @override
  Stream<int> batteryLevel(String deviceId) {
    final controller = _batteryController(deviceId);
    final initial = initialBatteryFor[deviceId];
    if (initial != null) {
      scheduleMicrotask(() => controller.add(initial));
    }
    return controller.stream;
  }

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

  /// Records all Control commands written for [deviceId], in order.
  List<List<int>> allControlWrites(String deviceId) =>
      List.unmodifiable(_allControlWrites[deviceId] ?? const []);

  /// Number of disconnect attempts issued for [deviceId].
  int disconnectCount(String deviceId) => _disconnectCounts[deviceId] ?? 0;

  @override
  Future<void> writeControl(String deviceId, List<int> bytes) async {
    _lastControlWrites[deviceId] = bytes;
    (_allControlWrites[deviceId] ??= []).add(bytes);
    if (bytes.isNotEmpty && bytes[0] == 0x02) {
      final remaining = _remainingStopWriteFailures[deviceId] ?? 0;
      if (remaining > 0) {
        _remainingStopWriteFailures[deviceId] = remaining - 1;
        throw StateError('Injected STOP write failure for $deviceId');
      }
    }
    if (autoAcknowledgeControls && bytes.isNotEmpty) {
      if (bytes[0] == 0x01) {
        _syncController(deviceId).add(List<int>.filled(13, 0)..[0] = 0x30);
      } else if (bytes[0] == 0x02) {
        _syncController(deviceId).add(List<int>.filled(9, 0)..[0] = 0x40);
      }
    }
  }

  final Map<String, List<int>> _lastControlWrites = {};
  final Map<String, List<List<int>>> _allControlWrites = {};
  final Map<String, int> _disconnectCounts = {};

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
