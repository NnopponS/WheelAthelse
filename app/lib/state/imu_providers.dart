import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wheelathlete/ble/imu_packet.dart';
import 'package:wheelathlete/state/ble_providers.dart';
import 'package:wheelathlete/state/imu_presentation_buffer.dart';
import 'package:wheelathlete/state/sample_hub.dart';
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
  static const int chartBufferCap = 200;

  WheelImuState copyWith({
    bool? streaming,
    ImuReading? latest,
    int? sampleCount,
    int? dropCount,
    Object? error = _unset,
    List<ImuReading>? recent,
  }) => WheelImuState(
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
  ImuStreamState({Map<WheelSide, WheelImuState>? bySide})
    : bySide = {
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
/// **Throttling**: BLE callbacks append to an O(1), fixed-capacity circular
/// buffer. Chart history is copied only at [imuEmitIntervalProvider], never for
/// every sample. This prevents presentation work from blocking the lossless
/// recording sink during sustained dual-wheel acquisition.
class ImuStreamNotifier extends Notifier<ImuStreamState> {
  final _subs = <WheelSide, StreamSubscription<HubSample>>{};
  final _buffers = <WheelSide, ImuPresentationBuffer>{};

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
      _buffers.clear();
      _timers.clear();
    });
    return ImuStreamState.initial();
  }

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
    _buffers[side] = ImuPresentationBuffer(
      capacity: WheelImuState.chartBufferCap,
    );
    state = state.copyWithSide(side, const WheelImuState(streaming: true));

    final hub = ref.read(imuSampleHubProvider);
    // Attach the presentation consumer before opening the raw BLE channel.
    // lastValueStream may synchronously replay its cached value on listen.
    // Subscribing downstream first prevents that first packet from falling
    // into the gap between hub.start() and samples.listen().
    final subscription = hub
        .samples(side)
        .listen(
          (event) {
            try {
              if (!ref.mounted) return;
              _buffers[side]!.add(
                event.sample.toReading(info),
                dropCount: hub.metrics(side).unrecoveredSamples,
              );
              _scheduleFlush(side);
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
    _subs[side] = subscription;
    try {
      await hub.start(side);
    } on Object {
      await _subs.remove(side)?.cancel();
      rethrow;
    }
  }

  void _scheduleFlush(WheelSide side) {
    final interval = _emitInterval;
    if (interval == Duration.zero) {
      _flushNow(side);
      return;
    }
    _timers[side] ??= Timer(interval, () => _flushNow(side));
  }

  /// Creates one ordered chart snapshot at presentation frequency.
  void _flushNow(WheelSide side) {
    _timers[side]?.cancel();
    _timers.remove(side);
    final buffer = _buffers[side];
    if (buffer == null || !ref.mounted) return;
    final snapshot = buffer.snapshot();
    final current = state.bySide[side]!;
    state = state.copyWithSide(
      side,
      current.copyWith(
        latest: snapshot.latest,
        sampleCount: snapshot.sampleCount,
        dropCount: snapshot.dropCount,
        error: null,
        recent: snapshot.recent,
      ),
    );
  }

  /// Stops streaming for [side]. The last [ImuReading] is retained so the UI
  /// can keep showing it. No-op if not streaming.
  Future<void> stop(WheelSide side) async {
    await _subs[side]?.cancel();
    _subs.remove(side);
    await ref.read(imuSampleHubProvider).stop(side);
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
/// Defaults to 10 Hz in production. BLE acquisition remains notification
/// driven and lossless; only presentation snapshots are throttled so two
/// wheels do not contend with Android's BLE callback delivery on the UI
/// isolate. Tests override this to [Duration.zero] for synchronous assertions.
final imuEmitIntervalProvider = Provider<Duration>(
  (ref) => const Duration(milliseconds: 100),
  name: 'imuEmitIntervalProvider',
);

final imuStreamProvider = NotifierProvider<ImuStreamNotifier, ImuStreamState>(
  ImuStreamNotifier.new,
);
