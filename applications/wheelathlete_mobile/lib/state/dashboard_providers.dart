import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wheelathlete/ble/control_command.dart';
import 'package:wheelathlete/state/ble_providers.dart';
import 'package:wheelathlete/theme/theme.dart';
import 'package:wheelathlete/widgets/connection_card.dart';

@immutable
class DashboardBoardSettings {
  const DashboardBoardSettings({
    this.rateHz = 100,
    this.accelRange = 1, // ±4g
    this.gyroRange = 3, // ±2000°/s
    this.isApplying = false,
    this.feedbackMessage,
  });

  final int rateHz;
  final int accelRange;
  final int gyroRange;
  final bool isApplying;
  final String? feedbackMessage;

  DashboardBoardSettings copyWith({
    int? rateHz,
    int? accelRange,
    int? gyroRange,
    bool? isApplying,
    Object? feedbackMessage = _unset,
  }) => DashboardBoardSettings(
    rateHz: rateHz ?? this.rateHz,
    accelRange: accelRange ?? this.accelRange,
    gyroRange: gyroRange ?? this.gyroRange,
    isApplying: isApplying ?? this.isApplying,
    feedbackMessage: identical(feedbackMessage, _unset)
        ? this.feedbackMessage
        : feedbackMessage as String?,
  );

  static const Object _unset = Object();
}

class DashboardSettingsNotifier extends Notifier<DashboardBoardSettings> {
  @override
  DashboardBoardSettings build() => const DashboardBoardSettings();

  void setRate(int rateHz) {
    state = state.copyWith(rateHz: rateHz);
  }

  void setAccelRange(int rangeIndex) {
    state = state.copyWith(accelRange: rangeIndex);
  }

  void setGyroRange(int rangeIndex) {
    state = state.copyWith(gyroRange: rangeIndex);
  }

  Future<void> applyToSide(WheelSide side) async {
    final connState = ref.read(connectionManagerProvider);
    final conn = connState.bySide[side];
    final deviceId = conn?.deviceId;
    if (conn == null || conn.status != ConnectionStatus.connected || deviceId == null) {
      state = state.copyWith(
        feedbackMessage: '${side.label} is not connected.',
      );
      return;
    }

    state = state.copyWith(isApplying: true, feedbackMessage: null);
    try {
      final ble = ref.read(bleRepositoryProvider);
      await ble.writeControl(deviceId, ControlCommand.setRate(state.rateHz));
      await ble.writeControl(
        deviceId,
        ControlCommand.setRange(
          accelRange: state.accelRange,
          gyroRange: state.gyroRange,
        ),
      );
      state = state.copyWith(
        isApplying: false,
        feedbackMessage: 'Applied ${state.rateHz} Hz & ranges to ${side.label}.',
      );
    } on Object catch (e) {
      state = state.copyWith(
        isApplying: false,
        feedbackMessage: 'Failed to configure ${side.label}: $e',
      );
    }
  }

  Future<void> applyToAllConnected() async {
    final connState = ref.read(connectionManagerProvider);
    final connectedSides = WheelSide.values.where(
      (side) =>
          connState.bySide[side]?.status == ConnectionStatus.connected &&
          connState.bySide[side]?.deviceId != null,
    ).toList();

    if (connectedSides.isEmpty) {
      state = state.copyWith(feedbackMessage: 'No sensors connected.');
      return;
    }

    state = state.copyWith(isApplying: true, feedbackMessage: null);
    try {
      final ble = ref.read(bleRepositoryProvider);
      for (final side in connectedSides) {
        final deviceId = connState.bySide[side]!.deviceId!;
        await ble.writeControl(deviceId, ControlCommand.setRate(state.rateHz));
        await ble.writeControl(
          deviceId,
          ControlCommand.setRange(
            accelRange: state.accelRange,
            gyroRange: state.gyroRange,
          ),
        );
      }
      state = state.copyWith(
        isApplying: false,
        feedbackMessage:
            'Applied settings to ${connectedSides.map((s) => s.shortLabel).join(', ')}.',
      );
    } on Object catch (e) {
      state = state.copyWith(
        isApplying: false,
        feedbackMessage: 'Configuration error: $e',
      );
    }
  }
}

final dashboardSettingsProvider =
    NotifierProvider<DashboardSettingsNotifier, DashboardBoardSettings>(
      DashboardSettingsNotifier.new,
    );
