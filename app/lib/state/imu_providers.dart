import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wheelathlete/ble/ble_repository.dart';
import 'package:wheelathlete/ble/imu_packet.dart';
import 'package:wheelathlete/state/ble_providers.dart';
import 'package:wheelathlete/theme/theme.dart';

/// Per-wheel realtime IMU state surfaced to the UI.
///
/// `latest` is the most recent [ImuReading] (physical units) — null until the
/// first sample arrives. `sampleCount` and `dropCount` accumulate across
/// batches for the lifetime of the current streaming session (reset on
/// [ImuStreamNotifier.start]).
class WheelImuState {
  const WheelImuState({
    this.streaming = false,
    this.latest,
    this.sampleCount = 0,
    this.dropCount = 0,
    this.error,
  });

  final bool streaming;
  final ImuReading? latest;
  final int sampleCount;
  final int dropCount;
  final String? error;

  WheelImuState copyWith({
    bool? streaming,
    ImuReading? latest,
    int? sampleCount,
    int? dropCount,
    Object? error = _unset,
  }) =>
      WheelImuState(
        streaming: streaming ?? this.streaming,
        // Keep the last reading when stopping — the UI shows it after stop.
        latest: latest ?? this.latest,
        sampleCount: sampleCount ?? this.sampleCount,
        dropCount: dropCount ?? this.dropCount,
        error: identical(error, _unset) ? this.error : error as String?,
      );

  static const Object _unset = Object();
}

/// Whole IMU-stream state: per-side snapshots.
class ImuStreamState {
  ImuStreamState({
    Map<WheelSide, WheelImuState>? bySide,
  }) : bySide = {
          WheelSide.left: bySide?[WheelSide.left] ?? const WheelImuState(),
          WheelSide.right: bySide?[WheelSide.right] ?? const WheelImuState(),
        };

  final Map<WheelSide, WheelImuState> bySide;

  ImuStreamState copyWithSide(WheelSide side, WheelImuState value) =>
      ImuStreamState(bySide: {...bySide, side: value});

  static ImuStreamState initial() => ImuStreamState();
}

/// Subscribes to the IMU Data notify stream for a connected wheel, parses
/// batches, tracks seq gaps, and exposes realtime [ImuReading]s to the UI.
///
/// Lifecycle:
/// - [start] resolves the device id + Info from [connectionManagerProvider],
///   resets the per-side counters, and subscribes to `BleRepository.imuData`.
/// - [stop] cancels the subscription but keeps `latest` so the UI can show
///   the last value after streaming ends.
/// - On stream error or parse error, the side is marked not-streaming with
///   an `error` message.
class ImuStreamNotifier extends Notifier<ImuStreamState> {
  final _subs = <WheelSide, StreamSubscription<List<int>>>{};
  final _trackers = <WheelSide, ImuSeqTracker>{};

  @override
  ImuStreamState build() {
    ref.onDispose(() {
      for (final s in _subs.values) {
        s.cancel();
      }
      _subs.clear();
      _trackers.clear();
    });
    return ImuStreamState.initial();
  }

  BleRepository get _ble => ref.read(bleRepositoryProvider);

  /// Starts streaming IMU data for [side]. The wheel must already be
  /// connected (via [ConnectionManagerNotifier.connect]); otherwise an error
  /// is recorded and no stream is opened.
  Future<void> start(WheelSide side) async {
    final conn = ref.read(connectionManagerProvider).bySide[side]!;
    final deviceId = conn.deviceId;
    final info = conn.info;
    if (deviceId == null || info == null) {
      state = state.copyWithSide(
        side,
        const WheelImuState(streaming: false, error: 'Wheel not connected'),
      );
      return;
    }

    // Replace any existing subscription for this side.
    await _subs[side]?.cancel();
    _trackers[side] = ImuSeqTracker();
    state = state.copyWithSide(side, const WheelImuState(streaming: true));

    _subs[side] = _ble.imuData(deviceId).listen(
      (bytes) {
        final tracker = _trackers[side]!;
        try {
          final result = ImuPacketParser.parseBatchWithGaps(bytes, tracker);
          final latest = result.samples.last.toReading(info);
          if (!ref.mounted) return;
          final cur = state.bySide[side]!;
          state = state.copyWithSide(
            side,
            cur.copyWith(
              streaming: true,
              latest: latest,
              sampleCount: cur.sampleCount + result.samples.length,
              dropCount: cur.dropCount + result.newGaps,
              error: null,
            ),
          );
        } on Object catch (e) {
          if (!ref.mounted) return;
          state = state.copyWithSide(
            side,
            state.bySide[side]!.copyWith(
              streaming: false,
              error: 'IMU parse error: $e',
            ),
          );
          _subs[side]?.cancel();
          _subs.remove(side);
        }
      },
      onError: (Object e) {
        if (!ref.mounted) return;
        state = state.copyWithSide(
          side,
          state.bySide[side]!.copyWith(
            streaming: false,
            error: 'IMU stream error: $e',
          ),
        );
        _subs.remove(side);
      },
    );
  }

  /// Stops streaming for [side]. The last [ImuReading] is retained so the UI
  /// can keep showing it. No-op if not streaming.
  Future<void> stop(WheelSide side) async {
    await _subs[side]?.cancel();
    _subs.remove(side);
    if (!ref.mounted) return;
    final cur = state.bySide[side]!;
    if (!cur.streaming) return;
    state = state.copyWithSide(side, cur.copyWith(streaming: false));
  }
}

final imuStreamProvider =
    NotifierProvider<ImuStreamNotifier, ImuStreamState>(
  ImuStreamNotifier.new,
);
