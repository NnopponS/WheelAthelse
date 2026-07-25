import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wheelathlete/state/ble_providers.dart';
import 'package:wheelathlete/state/imu_providers.dart';
import 'package:wheelathlete/state/sample_hub.dart';
import 'package:wheelathlete/state/sync_providers.dart';
import 'package:wheelathlete/theme/theme.dart';
import 'package:wheelathlete/widgets/connection_card.dart';

enum LiveAcquisitionStatus { idle, starting, live, degraded, stopping, failed }

class LiveAcquisitionState {
  const LiveAcquisitionState({
    this.status = LiveAcquisitionStatus.idle,
    this.activeSides = const {},
    this.failedSide,
    this.error,
  });
  final LiveAcquisitionStatus status;
  final Set<WheelSide> activeSides;
  final WheelSide? failedSide;
  final String? error;
  bool get active =>
      status == LiveAcquisitionStatus.starting ||
      status == LiveAcquisitionStatus.live ||
      status == LiveAcquisitionStatus.degraded;

  /// Whether the Start/Stop control may accept another user action.
  bool get canToggle =>
      status != LiveAcquisitionStatus.starting &&
      status != LiveAcquisitionStatus.stopping;
}

final liveAckTimeoutProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 2),
);

class LiveAcquisitionNotifier extends Notifier<LiveAcquisitionState> {
  bool _operationInFlight = false;
  @override
  LiveAcquisitionState build() => const LiveAcquisitionState();

  Future<void> start() async {
    if (_operationInFlight || state.active || !state.canToggle) return;
    _operationInFlight = true;
    final connections = ref.read(connectionManagerProvider);
    final sides = WheelSide.values
        .where(
          (side) =>
              connections.bySide[side]!.status == ConnectionStatus.connected,
        )
        .toSet();
    if (sides.isEmpty) return;
    state = LiveAcquisitionState(
      status: LiveAcquisitionStatus.starting,
      activeSides: sides,
    );
    final sync = ref.read(syncEngineProvider.notifier);
    final imu = ref.read(imuStreamProvider.notifier);
    final before = {
      for (final side in sides)
        side: ref.read(syncEngineProvider).bySide[side]!.lastStartFiredUs,
    };
    try {
      await Future.wait(
        sides.map((side) async {
          await sync.startListening(side);
          await imu.start(side);
        }),
      );
      for (final side in sides) {
        final deviceId = connections.bySide[side]!.deviceId;
        if (deviceId != null) {
          ref
              .read(connectionManagerProvider.notifier)
              .setAcquiring(deviceId, true);
        }
      }
      await Future.wait(
        sides.map((side) {
          final deviceId = connections.bySide[side]!.deviceId;
          return deviceId == null
              ? Future<void>.value()
              : ref.read(bleRepositoryProvider).prepareForStreaming(deviceId);
        }),
      );
      await Future.wait(
        sides.map((side) => sync.sendStart(side, targetStartUs: 0)),
      );
      final waits = {
        for (final side in sides)
          side: sync.waitForStart(
            side,
            previous: before[side],
            timeout: ref.read(liveAckTimeoutProvider),
          ),
      };
      final results = await Future.wait(
        sides.map((side) async => (side, await waits[side]!)),
      );
      final missing = results.where((r) => !r.$2).map((r) => r.$1).toList();
      if (missing.isNotEmpty) {
        await _rollback(sides);
        if (!ref.mounted) return;
        state = LiveAcquisitionState(
          status: LiveAcquisitionStatus.failed,
          activeSides: const {},
          failedSide: missing.first,
          error:
              'START not acknowledged by ${missing.map((s) => s.name).join(', ')}',
        );
        return;
      }
      if (ref.mounted) {
        state = LiveAcquisitionState(
          status: LiveAcquisitionStatus.live,
          activeSides: sides,
        );
      }
    } on Object catch (error) {
      await _rollback(sides);
      if (ref.mounted) {
        state = LiveAcquisitionState(
          status: LiveAcquisitionStatus.failed,
          error: 'Live start failed: $error',
        );
      }
    } finally {
      _operationInFlight = false;
    }
  }

  Future<void> stop() async {
    if (_operationInFlight || !state.active || !state.canToggle) return;
    _operationInFlight = true;
    final sides = Set<WheelSide>.of(state.activeSides);
    if (sides.isEmpty) {
      _operationInFlight = false;
      return;
    }
    state = LiveAcquisitionState(
      status: LiveAcquisitionStatus.stopping,
      activeSides: sides,
    );
    final sync = ref.read(syncEngineProvider.notifier);
    final imu = ref.read(imuStreamProvider.notifier);
    final manager = ref.read(connectionManagerProvider.notifier);
    final deviceIds = {
      for (final side in sides)
        side: ref.read(connectionManagerProvider).bySide[side]!.deviceId,
    };
    final before = {
      for (final side in sides)
        side: ref.read(syncEngineProvider).bySide[side]!.lastStopFiredUs,
    };
    final acknowledged = <WheelSide>{};
    final forcedDisconnects = <WheelSide>{};
    final unresolved = <WheelSide>{};
    try {
      Future<void> disconnectForSafety(WheelSide side) async {
        try {
          await manager.disconnect(side);
          forcedDisconnects.add(side);
        } on Object {
          unresolved.add(side);
        }
      }

      // Quiesce bounded replay recovery before STOP so the control write is
      // never queued behind a newly scheduled replay request.
      final hub = ref.read(imuSampleHubProvider);
      await Future.wait(sides.map(hub.suspendReplay));

      // Serial writes avoid competing for Android GATT resources while both
      // high-rate notification streams are active.
      final written = <WheelSide>{};
      for (final side in sides) {
        final result = await sync.sendStopWithRetry(side);
        if (result.written) {
          written.add(side);
        } else {
          await disconnectForSafety(side);
        }
      }

      // Once both writes have been issued, wait concurrently so a lost ACK
      // from one wheel never delays the other wheel's physical STOP.
      final ackResults = await Future.wait(
        written.map(
          (side) async => (
            side,
            await sync.waitForStop(
              side,
              previous: before[side],
              timeout: ref.read(liveAckTimeoutProvider),
            ),
          ),
        ),
      );
      for (final (side, wasAcknowledged) in ackResults) {
        if (wasAcknowledged) {
          acknowledged.add(side);
        } else {
          // Firmware stops acquisition on disconnect. Do not tear down the
          // local stream until STOP_FIRED or this safety path succeeds.
          await disconnectForSafety(side);
        }
      }

      final physicallyStopped = {...acknowledged, ...forcedDisconnects};
      if (physicallyStopped.isNotEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await Future.wait(physicallyStopped.map(imu.stop));
      }

      for (final side in acknowledged) {
        final deviceId = deviceIds[side];
        if (deviceId != null) manager.setAcquiring(deviceId, false);
      }

      if (!ref.mounted) return;
      if (unresolved.isNotEmpty) {
        state = LiveAcquisitionState(
          status: LiveAcquisitionStatus.degraded,
          activeSides: unresolved,
          failedSide: unresolved.first,
          error:
              'STOP failed and safety disconnect failed for '
              '${unresolved.map((side) => side.name).join(', ')}',
        );
      } else if (forcedDisconnects.isNotEmpty) {
        state = LiveAcquisitionState(
          status: LiveAcquisitionStatus.failed,
          failedSide: forcedDisconnects.first,
          error:
              'STOP failed for '
              '${forcedDisconnects.map((side) => side.name).join(', ')}; '
              'disconnected for safety',
        );
      } else {
        state = const LiveAcquisitionState();
      }
    } finally {
      _operationInFlight = false;
    }
  }

  Future<void> _rollback(Set<WheelSide> sides) async {
    final sync = ref.read(syncEngineProvider.notifier);
    final hub = ref.read(imuSampleHubProvider);
    await Future.wait(sides.map(hub.suspendReplay));
    await Future.wait(
      sides.map((side) async {
        try {
          await sync.sendStop(side);
        } on Object {
          /* best effort */
        }
      }),
    );
    final imu = ref.read(imuStreamProvider.notifier);
    await Future.wait(sides.map(imu.stop));
    for (final side in sides) {
      final deviceId = ref
          .read(connectionManagerProvider)
          .bySide[side]!
          .deviceId;
      if (deviceId != null) {
        ref
            .read(connectionManagerProvider.notifier)
            .setAcquiring(deviceId, false);
      }
    }
  }
}

Future<void> imuStopBestEffort(WheelSide side) async {}

final liveAcquisitionProvider =
    NotifierProvider<LiveAcquisitionNotifier, LiveAcquisitionState>(
      LiveAcquisitionNotifier.new,
    );
