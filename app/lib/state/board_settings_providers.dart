import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wheelathlete/ble/ble_repository.dart';
import 'package:wheelathlete/ble/board_config.dart';
import 'package:wheelathlete/ble/control_command.dart';
import 'package:wheelathlete/state/ble_providers.dart';
import 'package:wheelathlete/theme/theme.dart';

/// State for the Board Settings screen.
class BoardSettingsState {
  const BoardSettingsState({
    this.status = BoardSettingsStatus.loading,
    this.config,
    this.error,
  });

  final BoardSettingsStatus status;
  final BoardConfig? config;
  final String? error;
}

enum BoardSettingsStatus { loading, loaded, saving, saved, error }

/// Notifier that reads the Config characteristic on build and writes
/// SET_NAME / SET_WHEEL / SET_RATE commands on save.
///
/// Constructed per [WheelSide] via [boardSettingsProvider].
class BoardSettingsNotifier extends Notifier<BoardSettingsState> {
  BoardSettingsNotifier(this.side);

  final WheelSide side;

  @override
  BoardSettingsState build() {
    // Check if the wheel is connected before scheduling the async load.
    final conn = ref.read(connectionManagerProvider).bySide[side]!;
    if (conn.deviceId == null) {
      return const BoardSettingsState(
        status: BoardSettingsStatus.error,
        error: 'Wheel not connected',
      );
    }
    // Load the current config asynchronously.
    Future<void>.delayed(Duration.zero, _loadConfig);
    return const BoardSettingsState();
  }

  BleRepository get _ble => ref.read(bleRepositoryProvider);

  Future<void> _loadConfig() async {
    final conn = ref.read(connectionManagerProvider).bySide[side]!;
    final deviceId = conn.deviceId;
    if (deviceId == null) {
      state = const BoardSettingsState(
        status: BoardSettingsStatus.error,
        error: 'Wheel not connected',
      );
      return;
    }
    try {
      final config = await _ble.readConfig(deviceId);
      if (!ref.mounted) return;
      state = BoardSettingsState(
        status: BoardSettingsStatus.loaded,
        config: config,
      );
    } on Object catch (e) {
      if (!ref.mounted) return;
      state = BoardSettingsState(
        status: BoardSettingsStatus.error,
        error: '$e',
      );
    }
  }

  /// Writes SET_NAME, SET_WHEEL, and SET_RATE commands to the board.
  /// After writing, re-reads the Config characteristic to confirm the
  /// changes took effect and updates the displayed config.
  Future<void> save({
    required String name,
    required int wheelByte,
    required int rateHz,
  }) async {
    final conn = ref.read(connectionManagerProvider).bySide[side]!;
    final deviceId = conn.deviceId;
    if (deviceId == null) {
      state = const BoardSettingsState(
        status: BoardSettingsStatus.error,
        error: 'Wheel not connected',
      );
      return;
    }
    state = BoardSettingsState(
      status: BoardSettingsStatus.saving,
      config: state.config,
    );
    try {
      // Write commands with a small delay between each to avoid BLE stack
      // write-queue issues when sending multiple writes in rapid succession.
      await _ble.writeControl(deviceId, ControlCommand.setName(name));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await _ble.writeControl(deviceId, ControlCommand.setWheel(wheelByte));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await _ble.writeControl(deviceId, ControlCommand.setRate(rateHz));
      // Re-read the Config characteristic to confirm changes and update UI.
      final updatedConfig = await _ble.readConfig(deviceId);
      if (!ref.mounted) return;
      state = BoardSettingsState(
        status: BoardSettingsStatus.saved,
        config: updatedConfig,
      );
    } on Object catch (e) {
      if (!ref.mounted) return;
      state = BoardSettingsState(
        status: BoardSettingsStatus.error,
        config: state.config,
        error: '$e',
      );
    }
  }
}

final boardSettingsProvider =
    NotifierProvider.family<BoardSettingsNotifier, BoardSettingsState, WheelSide>(
  BoardSettingsNotifier.new,
);
