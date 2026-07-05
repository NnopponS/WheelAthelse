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
/// [ImuStreamNotifier.start]). `recent` is a rolling ring buffer of the last
/// ~300 readings used by the realtime charts (subtask #19).
class WheelImuState {
  const WheelImuState({
    this.streaming = false,
    this.latest,
    this.sampleCount = 0,
    this.dropCount = 0,
    this.error,
    this.recent = const [],
  });

  final bool streaming;
  final ImuReading? latest;
  final int sampleCount;
  final int dropCount;
  final String? error;

  /// Rolling buffer of recent readings (capped at [_chartBufferCap]) for the
  /// realtime line charts.
  final List<ImuReading> recent;

  /// Maximum number of readings kept in [recent] (≈3 s at 100 Hz).
  static const int chartBufferCap = 300;

  WheelImuState copyWith({
    bool? streaming,
    ImuReading? latest,
    int? sampleCount,
    int? dropCount,
    Object? error = _unset,
    List<ImuReading>? recent,
  }) =>
      WheelImuState(
        streaming: streaming ?? this.streaming,
        // Keep the last reading when stopping — the UI shows it after stop.
        latest: latest ?? this.latest,
        sampleCount: sampleCount ?? this.sampleCount,
        dropCount: dropCount ?? this.dropCount,
        error: identical(error, _unset) ? this.error : error as String?,
        recent: recent ?? this.recent,
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
///
/// **Throttling**: To avoid flooding the UI with state emissions on every BLE
/// notification batch (which at 100 Hz × 2 boards can be 50–100+ batches/sec
/// and saturate the main isolate, causing BLE notification processing delays
/// and app-side packet drops), state is emitted at most once per
/// [imuEmitIntervalProvider] interval. The internal accumulators (`latest`,
/// `sampleCount`, `dropCount`, `recent`) are always updated immediately; only
/// the `state =` assignment is throttled. When the interval is [Duration.zero]
/// (the test default), every batch emits immediately.
class ImuStreamNotifier extends Notifier<ImuStreamState> {
  final _subs = <WheelSide, StreamSubscription<List<int>>>{};
  final _trackers = <WheelSide, ImuSeqTracker>{};

  /// Per-side "dirty" snapshot holding the latest accumulated values that have
  /// not yet been pushed to `state`. Null when there is no pending update.
  final _pending = <WheelSide, WheelImuState>{};

  /// Active throttle timer per side, or null when no flush is scheduled.
  final _timers = <WheelSide, Timer>{};

  @override
  ImuStreamState build() {
    ref.onDispose(() {
      for (final s in _subs.values) {
        s.cancel();
      }
      for (final t in _timers.values) {
        t.cancel();
      }
      _subs.clear();
      _trackers.clear();
      _pending.clear();
      _timers.clear();
    });
    return ImuStreamState.initial();
  }

  BleRepository get _ble => ref.read(bleRepositoryProvider);

  Duration get _emitInterval => ref.read(imuEmitIntervalProvider);

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
    _timers[side]?.cancel();
    _timers.remove(side);
    _pending.remove(side);
    _trackers[side] = ImuSeqTracker();
    state = state.copyWithSide(side, const WheelImuState(streaming: true));

    _subs[side] = _ble.imuData(deviceId).listen(
      (bytes) {
        final tracker = _trackers[side]!;
        try {
          final result = ImuPacketParser.parseBatchWithGaps(bytes, tracker);
          final readings =
              result.samples.map((s) => s.toReading(info)).toList();
          final latest = readings.last;
          if (!ref.mounted) return;
          final cur = _pending[side] ?? state.bySide[side]!;
          // Append to the rolling chart buffer + cap.
          // Optimization: use sublist on the existing buffer + concat new
          // readings, instead of [...cur.recent, ...readings] which copies
          // the entire buffer every batch. This reduces per-batch allocation
          // from O(buffer+batch) to O(cap+batch) with one fewer intermediate.
          const cap = WheelImuState.chartBufferCap;
          final needed = cur.recent.length + readings.length;
          final buffer = needed <= cap
              ? [...cur.recent, ...readings]
              : (cur.recent.length >= cap
                  ? [...cur.recent.sublist(needed - cap), ...readings]
                  : [...cur.recent, ...readings.sublist(0, cap - cur.recent.length)]);
          final next = cur.copyWith(
            streaming: true,
            latest: latest,
            sampleCount: cur.sampleCount + result.samples.length,
            dropCount: cur.dropCount + result.newGaps,
            error: null,
            recent: buffer,
          );
          _emitOrDefer(side, next);
        } on Object catch (e) {
          if (!ref.mounted) return;
          _flushNow(side);
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
        _flushNow(side);
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

  /// Either emits [next] immediately (when interval is zero or no timer is
  /// running) or stashes it as the pending snapshot and schedules a flush.
  void _emitOrDefer(WheelSide side, WheelImuState next) {
    final interval = _emitInterval;
    if (interval == Duration.zero) {
      // Immediate mode: emit every batch (test default).
      _pending.remove(side);
      state = state.copyWithSide(side, next);
      return;
    }
    _pending[side] = next;
    // Schedule a flush if one isn't already pending.
    _timers[side] ??= Timer(interval, () => _flushNow(side));
  }

  /// Pushes the pending snapshot (if any) to `state` and clears the timer.
  void _flushNow(WheelSide side) {
    _timers[side]?.cancel();
    _timers.remove(side);
    final pending = _pending.remove(side);
    if (pending != null && ref.mounted) {
      state = state.copyWithSide(side, pending);
    }
  }

  /// Stops streaming for [side]. The last [ImuReading] is retained so the UI
  /// can keep showing it. No-op if not streaming.
  Future<void> stop(WheelSide side) async {
    await _subs[side]?.cancel();
    _subs.remove(side);
    // Flush any pending update so the final state is consistent.
    _flushNow(side);
    if (!ref.mounted) return;
    final cur = state.bySide[side]!;
    if (!cur.streaming) return;
    state = state.copyWithSide(side, cur.copyWith(streaming: false));
  }
}

/// Minimum interval between `state` emissions from [ImuStreamNotifier].
///
/// Defaults to ~33 ms (≈30 Hz) in production. Tests override this to
/// [Duration.zero] so they can assert on synchronous state updates.
final imuEmitIntervalProvider = Provider<Duration>(
  (ref) => const Duration(milliseconds: 33),
  name: 'imuEmitIntervalProvider',
);

final imuStreamProvider =
    NotifierProvider<ImuStreamNotifier, ImuStreamState>(
  ImuStreamNotifier.new,
);
