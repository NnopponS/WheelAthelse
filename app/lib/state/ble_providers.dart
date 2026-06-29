import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wheelathlete/ble/ble_repository.dart';
import 'package:wheelathlete/ble/device_info.dart';
import 'package:wheelathlete/theme/theme.dart';
import 'package:wheelathlete/widgets/connection_card.dart';

/// Constructs the production [BleRepository]. Override in tests with a
/// [FakeBleRepository] via `bleRepositoryProvider.overrideWith((ref) => fake)`.
final bleRepositoryProvider = Provider<BleRepository>(
  (ref) => FlutterBluePlusBleRepository(),
);

/// Per-side connection snapshot shown in the ConnectionCard.
class WheelConnection {
  const WheelConnection({
    this.status = ConnectionStatus.disconnected,
    this.deviceId,
    this.deviceName,
    this.rssi,
    this.info,
  });

  final ConnectionStatus status;

  /// Platform remote id of the connected device, or null when disconnected.
  /// Needed to issue disconnect / read RSSI without re-scanning.
  final String? deviceId;
  final String? deviceName;
  final int? rssi;
  final DeviceInfo? info;

  WheelConnection copyWith({
    ConnectionStatus? status,
    String? deviceId,
    String? deviceName,
    int? rssi,
    DeviceInfo? info,
  }) =>
      WheelConnection(
        status: status ?? this.status,
        deviceId: deviceId ?? this.deviceId,
        deviceName: deviceName ?? this.deviceName,
        rssi: rssi ?? this.rssi,
        info: info ?? this.info,
      );
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

  @override
  ConnectionManagerState build() {
    // Clean up scan + connection subscriptions when the notifier is disposed.
    ref.onDispose(() {
      _scanSub?.cancel();
      for (final s in _connSubs.values) {
        s.cancel();
      }
      _connSubs.clear();
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
  Future<void> connect(String deviceId) async {
    if (!ref.mounted) return;
    state = state.copyWith(error: null);
    try {
      final conn = await _ble.connect(deviceId);
      if (!ref.mounted) return;
      final side = conn.info.wheelId.toWheelSide();
      state = state.copyWith(
        bySide: {
          ...state.bySide,
          side: WheelConnection(
            status: ConnectionStatus.connected,
            deviceId: conn.id,
            deviceName: conn.name,
            info: conn.info,
          ),
        },
      );
      _watchConnection(deviceId, side);
    } on Object catch (e) {
      if (ref.mounted) state = state.copyWith(error: '$e');
    }
  }

  Future<void> disconnect(WheelSide side) async {
    final conn = state.bySide[side];
    final deviceId = conn?.deviceId;
    if (deviceId == null) return;
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
}


final connectionManagerProvider =
    NotifierProvider<ConnectionManagerNotifier, ConnectionManagerState>(
  ConnectionManagerNotifier.new,
);
