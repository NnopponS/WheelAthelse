import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wheelathlete/ble/ble_repository.dart';
import 'package:wheelathlete/ble/device_info.dart';
import 'package:wheelathlete/records/storage_repository.dart';
import 'package:wheelathlete/theme/theme.dart';
import 'package:wheelathlete/widgets/connection_card.dart';

/// Constructs the production [BleRepository]. Override in tests with a
/// [FakeBleRepository] via `bleRepositoryProvider.overrideWith((ref) => fake)`.
final bleRepositoryProvider = Provider<BleRepository>(
  (ref) => FlutterBluePlusBleRepository(),
);

/// Interval for periodic RSSI polling after connect. Set to null to
/// disable polling (useful in tests to avoid pending timers). Defaults to
/// 2 seconds in production.
final rssiPollIntervalProvider = Provider<Duration?>(
  (ref) => const Duration(seconds: 2),
);

/// Settle delay inserted after connecting the second of two boards, before
/// subscribing to notify streams. Gives the Android BLE stack time to
/// rebalance the connection schedule. Set to [Duration.zero] in tests to
/// avoid fake-async timeouts.
final interConnectSettleDelayProvider = Provider<Duration>(
  (ref) => const Duration(milliseconds: 500),
);

/// Constructs the production [StorageRepository]. Override in tests with an
/// [InMemoryStorageRepository] via `storageRepositoryProvider.overrideWith`.
final storageRepositoryProvider = Provider<StorageRepository>(
  (ref) => PathProviderStorageRepository(),
);

/// Per-side connection snapshot shown in the ConnectionCard.
class WheelConnection {
  const WheelConnection({
    this.status = ConnectionStatus.disconnected,
    this.deviceId,
    this.deviceName,
    this.rssi,
    this.batteryPercent,
    this.info,
  });

  final ConnectionStatus status;

  /// Platform remote id of the connected device, or null when disconnected.
  /// Needed to issue disconnect / read RSSI without re-scanning.
  final String? deviceId;
  final String? deviceName;
  final int? rssi;

  /// Battery level 0–100 from the Battery Service (0x2A19), or null when
  /// unknown / not yet received.
  final int? batteryPercent;
  final DeviceInfo? info;

  WheelConnection copyWith({
    ConnectionStatus? status,
    String? deviceId,
    String? deviceName,
    Object? rssi = _unset,
    Object? batteryPercent = _unset,
    DeviceInfo? info,
  }) =>
      WheelConnection(
        status: status ?? this.status,
        deviceId: deviceId ?? this.deviceId,
        deviceName: deviceName ?? this.deviceName,
        rssi: identical(rssi, _unset) ? this.rssi : rssi as int?,
        batteryPercent: identical(batteryPercent, _unset)
            ? this.batteryPercent
            : batteryPercent as int?,
        info: info ?? this.info,
      );

  static const Object _unset = Object();
}

/// Whole connection-manager state: scan results + per-side connections.
class ConnectionManagerState {
  ConnectionManagerState({
    this.isScanning = false,
    this.scanResults = const [],
    Map<WheelSide, WheelConnection>? bySide,
    this.error,
  }) : bySide = {
          WheelSide.left: bySide?[WheelSide.left] ?? const WheelConnection(),
          WheelSide.right: bySide?[WheelSide.right] ?? const WheelConnection(),
        };

  final bool isScanning;
  final List<ScannedDevice> scanResults;
  final Map<WheelSide, WheelConnection> bySide;
  final String? error;

  /// Sentinel so `copyWith` can distinguish "don't touch error" from
  /// "clear error to null". Pass `error: null` to clear; omit it to preserve.
  static const Object _unsetError = Object();

  ConnectionManagerState copyWith({
    bool? isScanning,
    List<ScannedDevice>? scanResults,
    Map<WheelSide, WheelConnection>? bySide,
    Object? error = _unsetError,
  }) =>
      ConnectionManagerState(
        isScanning: isScanning ?? this.isScanning,
        scanResults: scanResults ?? this.scanResults,
        bySide: bySide ?? this.bySide,
        error: identical(error, _unsetError) ? this.error : error as String?,
      );

  /// Sentinel: a fresh idle state with both wheels disconnected.
  static ConnectionManagerState initial() => ConnectionManagerState();
}

/// Manages BLE scan + connect/disconnect for both wheels.
///
/// Auto-assigns a connected device to L or R based on the `wheel_id` byte in
/// the Info characteristic (not on user choice) — this guarantees the side
/// matches the physical sensor even if the user tapped the wrong row.
class ConnectionManagerNotifier extends Notifier<ConnectionManagerState> {
  StreamSubscription<List<ScannedDevice>>? _scanSub;
  final _connSubs = <String, StreamSubscription<BleConnectionState>>{};
  final _batterySubs = <String, StreamSubscription<int>>{};
  final _rssiPolling = <String, bool>{}; // active flags for RSSI poll loops

  @override
  ConnectionManagerState build() {
    // Clean up scan + connection + battery subscriptions + RSSI polling
    // flags when the notifier is disposed.
    ref.onDispose(() {
      _scanSub?.cancel();
      for (final s in _connSubs.values) {
        s.cancel();
      }
      _connSubs.clear();
      for (final s in _batterySubs.values) {
        s.cancel();
      }
      _batterySubs.clear();
      _rssiPolling.clear();
    });
    return ConnectionManagerState();
  }

  BleRepository get _ble => ref.read(bleRepositoryProvider);

  Future<void> startScan() async {
    if (!ref.mounted) return;
    state = state.copyWith(isScanning: true, error: null);
    _scanSub = _ble.scanResults.listen(
      (results) {
        if (ref.mounted) state = state.copyWith(scanResults: results);
      },
      onError: (Object e) {
        if (ref.mounted) state = state.copyWith(error: '$e');
      },
    );
    try {
      await _ble.startScan(const Duration(seconds: 10));
    } on Object catch (e) {
      if (ref.mounted) state = state.copyWith(error: '$e');
    } finally {
      await _scanSub?.cancel();
      if (ref.mounted) state = state.copyWith(isScanning: false);
    }
  }

  Future<void> stopScan() async {
    await _ble.stopScan();
    await _scanSub?.cancel();
    if (ref.mounted) state = state.copyWith(isScanning: false);
  }

  /// Connect to [deviceId]. The side (L/R) is decided by the device's
  /// `wheel_id`, not by the caller.
  ///
  /// When connecting the second of two boards, a short settle delay is
  /// inserted after the BLE connection is established. This gives the
  /// Android BLE stack time to rebalance the connection schedule across
  /// both peripherals before we start subscribing to notify streams.
  /// Without this delay, the second board's first notifications often
  /// arrive while the stack is still re-negotiating intervals, causing
  /// seq gaps and packet drops on the second board.
  Future<void> connect(String deviceId) async {
    if (!ref.mounted) return;
    final alreadyConnectedCount = state.bySide.values
        .where((c) => c.status == ConnectionStatus.connected)
        .length;
    state = state.copyWith(error: null);
    try {
      final conn = await _ble.connect(deviceId);
      if (!ref.mounted) return;
      final side = conn.info.wheelId.toWheelSide();
      // If another wheel is already connected, give the BLE stack a moment
      // to rebalance the connection schedule before we start polling RSSI
      // and subscribing to battery/IMU notifications on the new device.
      if (alreadyConnectedCount > 0) {
        final settleDelay = ref.read(interConnectSettleDelayProvider);
        if (settleDelay > Duration.zero) {
          await Future<void>.delayed(settleDelay);
          if (!ref.mounted) return;
        }
      }
      // Read RSSI immediately so the card shows signal strength right away.
      int? initialRssi;
      try {
        initialRssi = await _ble.readRssi(deviceId);
      } on Object {
        // RSSI read may fail on some platforms — non-fatal, leave null.
      }
      if (!ref.mounted) return;
      state = state.copyWith(
        bySide: {
          ...state.bySide,
          side: WheelConnection(
            status: ConnectionStatus.connected,
            deviceId: conn.id,
            deviceName: conn.name,
            rssi: initialRssi,
            info: conn.info,
          ),
        },
      );
      _watchConnection(deviceId, side);
      _subscribeBattery(deviceId, side);
      _startRssiPolling(deviceId, side);
    } on Object catch (e) {
      if (ref.mounted) state = state.copyWith(error: '$e');
    }
  }

  Future<void> disconnect(WheelSide side) async {
    final conn = state.bySide[side];
    final deviceId = conn?.deviceId;
    if (deviceId == null) return;
    _stopTelemetry(deviceId);
    await _ble.disconnect(deviceId);
    if (!ref.mounted) return;
    state = state.copyWith(
      bySide: {
        ...state.bySide,
        side: const WheelConnection(),
      },
    );
  }

  void _watchConnection(String deviceId, WheelSide side) {
    _connSubs[deviceId]?.cancel();
    _connSubs[deviceId] = _ble.connectionState(deviceId).listen((s) {
      if (!ref.mounted) return;
      if (s == BleConnectionState.disconnected) {
        _stopTelemetry(deviceId);
        state = state.copyWith(
          bySide: {
            ...state.bySide,
            side: const WheelConnection(),
          },
        );
        _connSubs.remove(deviceId)?.cancel();
      }
    });
  }

  /// Subscribes to the Battery Level notify stream (0x2A19) and updates the
  /// per-side [WheelConnection.batteryPercent] on each notification.
  void _subscribeBattery(String deviceId, WheelSide side) {
    _batterySubs[deviceId]?.cancel();
    _batterySubs[deviceId] = _ble.batteryLevel(deviceId).listen(
      (pct) {
        if (!ref.mounted) return;
        final cur = state.bySide[side]!;
        state = state.copyWith(
          bySide: {
            ...state.bySide,
            side: cur.copyWith(batteryPercent: pct),
          },
        );
      },
      onError: (Object e) {
        // Battery stream errors are non-fatal — the card just keeps the last
        // known value (or null).
      },
    );
  }

  /// Starts a periodic poll that reads RSSI at the interval from
  /// [rssiPollIntervalProvider] while the device is connected, updating
  /// [WheelConnection.rssi]. Uses a recursive [Future.delayed] loop
  /// guarded by a per-device flag so it stops cleanly when the device
  /// disconnects or the notifier is disposed. No-op if the interval
  /// provider returns null (used in tests to avoid pending timers).
  void _startRssiPolling(String deviceId, WheelSide side) {
    final interval = ref.read(rssiPollIntervalProvider);
    if (interval == null) return;
    _rssiPolling[deviceId] = true;
    _pollRssiLoop(deviceId, side, interval);
  }

  Future<void> _pollRssiLoop(
    String deviceId,
    WheelSide side,
    Duration interval,
  ) async {
    while (_rssiPolling[deviceId] == true && ref.mounted) {
      try {
        await Future<void>.delayed(interval);
        if (!ref.mounted || _rssiPolling[deviceId] != true) return;
        final rssi = await _ble.readRssi(deviceId);
        if (!ref.mounted || _rssiPolling[deviceId] != true) return;
        final cur = state.bySide[side]!;
        if (cur.deviceId != deviceId) return; // side reassigned
        state = state.copyWith(
          bySide: {
            ...state.bySide,
            side: cur.copyWith(rssi: rssi),
          },
        );
      } on Object {
        // RSSI read failure — non-fatal, keep last known value.
      }
    }
  }

  /// Stops battery subscription + RSSI polling for [deviceId].
  void _stopTelemetry(String deviceId) {
    _batterySubs.remove(deviceId)?.cancel();
    _rssiPolling[deviceId] = false;
  }
}


final connectionManagerProvider =
    NotifierProvider<ConnectionManagerNotifier, ConnectionManagerState>(
  ConnectionManagerNotifier.new,
);
