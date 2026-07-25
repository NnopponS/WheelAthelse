import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wheelathlete/ble/ble_repository.dart';
import 'package:wheelathlete/ble/control_command.dart';
import 'package:wheelathlete/ble/imu_packet.dart';
import 'package:wheelathlete/state/ble_providers.dart';
import 'package:wheelathlete/theme/theme.dart';

class HubSample {
  const HubSample({
    required this.sample,
    required this.receivedAtMs,
    required this.recovered,
  });
  final ImuSample sample;
  final int receivedAtMs;
  final bool recovered;
}

class RecoveryMetrics {
  const RecoveryMetrics({
    this.recoveredSamples = 0,
    this.unrecoveredSamples = 0,
    this.replayAttempts = 0,
    this.replayWriteFailures = 0,
  });
  final int recoveredSamples;
  final int unrecoveredSamples;
  final int replayAttempts;
  final int replayWriteFailures;
}

/// Orders live and replayed samples on one uint32 sequence timeline.
class SampleRecoveryBuffer {
  SampleRecoveryBuffer({
    required this.onSample,
    required this.onReplay,
    this.replaySupported = true,
    this.timeout = const Duration(milliseconds: 500),
  });

  final void Function(HubSample sample) onSample;
  final Future<void> Function(int startSeq, int count) onReplay;
  final bool replaySupported;
  final Duration timeout;
  final Map<int, ImuSample> _pending = {};
  final Set<int> _requested = {};
  int? _expected;
  Timer? _timer;
  int _attempt = 0;
  int _generation = 0;
  int _recovered = 0;
  int _unrecovered = 0;
  int _replayAttempts = 0;
  int _replayWriteFailures = 0;
  bool _replayInFlight = false;
  bool _replaySuspended = false;
  bool _disposed = false;
  Completer<void>? _replayIdle;

  static const _maxReplayAttempts = 3;

  RecoveryMetrics get metrics => RecoveryMetrics(
    recoveredSamples: _recovered,
    unrecoveredSamples: _unrecovered,
    replayAttempts: _replayAttempts,
    replayWriteFailures: _replayWriteFailures,
  );

  void add(ImuSample sample, int receivedAtMs) {
    final expected = _expected;
    if (expected == null) {
      _emit(sample, receivedAtMs);
      return;
    }
    if (sample.seq == expected) {
      _emit(sample, receivedAtMs);
      _drain(receivedAtMs);
      return;
    }
    final distance = (sample.seq - expected) & 0xFFFFFFFF;
    if (distance == 0 || distance >= 0x80000000) return; // duplicate/late
    _pending.putIfAbsent(sample.seq, () => sample);
    if (_pending.length > 512) _releaseGap(receivedAtMs);
    _requestGap();
  }

  void _emit(ImuSample sample, int receivedAtMs) {
    final recovered = _requested.remove(sample.seq);
    if (recovered) _recovered++;
    _expected = (sample.seq + 1) & 0xFFFFFFFF;
    onSample(
      HubSample(
        sample: sample,
        receivedAtMs: receivedAtMs,
        recovered: recovered,
      ),
    );
  }

  void _drain(int receivedAtMs) {
    while (true) {
      final expected = _expected;
      if (expected == null) break;
      final next = _pending.remove(expected);
      if (next == null) break;
      _emit(next, receivedAtMs);
    }
    if (_pending.isEmpty) {
      _resetGapCycle();
    } else {
      _requestGap();
    }
  }

  void _requestGap() {
    if (_disposed || _expected == null || _pending.isEmpty) return;
    if (_replaySuspended || !replaySupported) {
      _releaseGap(DateTime.now().millisecondsSinceEpoch);
      return;
    }
    if (_replayInFlight || _timer != null) return;
    final expected = _expected!;
    final nearest = _pending.keys.reduce(
      (a, b) =>
          ((a - expected) & 0xFFFFFFFF) < ((b - expected) & 0xFFFFFFFF) ? a : b,
    );
    final missing = ((nearest - expected) & 0xFFFFFFFF).clamp(1, 128);
    _attempt++;
    _replayAttempts++;
    _replayInFlight = true;
    final idle = Completer<void>();
    _replayIdle = idle;
    unawaited(
      _sendReplay(
        expected: expected,
        missing: missing,
        attempt: _attempt,
        generation: _generation,
        idle: idle,
      ),
    );
  }

  Future<void> _sendReplay({
    required int expected,
    required int missing,
    required int attempt,
    required int generation,
    required Completer<void> idle,
  }) async {
    var written = false;
    try {
      await onReplay(expected, missing);
      written = true;
    } on Object {
      // A rejected Android GATT write is recoverable transport pressure, not
      // an uncaught application error. The bounded retry below owns it.
      _replayWriteFailures++;
    }

    _replayInFlight = false;
    if (!_disposed && generation == _generation) {
      if (written) _markRequested(expected, missing);
      if (_pending.isNotEmpty) {
        _timer = Timer(_retryDelay(attempt), () {
          _timer = null;
          if (_disposed || _pending.isEmpty) return;
          if (!_replaySuspended && _attempt < _maxReplayAttempts) {
            _requestGap();
          } else {
            _releaseGap(DateTime.now().millisecondsSinceEpoch);
          }
        });
      } else {
        _resetGapCycle();
      }
    } else if (!_disposed && _pending.isNotEmpty) {
      _requestGap();
    }

    if (identical(_replayIdle, idle)) _replayIdle = null;
    if (!idle.isCompleted) idle.complete();
  }

  void _markRequested(int start, int count) {
    final currentExpected = _expected;
    if (currentExpected == null) return;
    for (var i = 0; i < count; i++) {
      final seq = (start + i) & 0xFFFFFFFF;
      final distance = (seq - currentExpected) & 0xFFFFFFFF;
      if (distance < 0x80000000) _requested.add(seq);
    }
  }

  Duration _retryDelay(int attempt) {
    var multiplier = 1;
    for (var i = 1; i < attempt && i < 3; i++) {
      multiplier *= 2;
    }
    return timeout * multiplier;
  }

  void _resetGapCycle() {
    _timer?.cancel();
    _timer = null;
    _attempt = 0;
    _generation++;
  }

  void _releaseGap(int receivedAtMs) {
    if (_expected == null || _pending.isEmpty) return;
    final expected = _expected!;
    final nearest = _pending.keys.reduce(
      (a, b) =>
          ((a - expected) & 0xFFFFFFFF) < ((b - expected) & 0xFFFFFFFF) ? a : b,
    );
    final missing = (nearest - expected) & 0xFFFFFFFF;
    _unrecovered += missing;
    for (var i = 0; i < missing; i++) {
      _requested.remove((expected + i) & 0xFFFFFFFF);
    }
    _expected = nearest;
    _resetGapCycle();
    _drain(receivedAtMs);
  }

  /// Prevents any new replay control writes and waits briefly for the one
  /// already in flight. STOP can then enter the GATT queue without replay
  /// retries competing with it.
  Future<void> suspendReplay({
    Duration drainTimeout = const Duration(milliseconds: 500),
  }) async {
    if (_disposed) return;
    _replaySuspended = true;
    _timer?.cancel();
    _timer = null;
    _generation++;
    if (_pending.isNotEmpty) {
      _releaseGap(DateTime.now().millisecondsSinceEpoch);
    }
    final active = _replayIdle;
    if (active != null) {
      await active.future.timeout(drainTimeout, onTimeout: () {});
    }
  }

  void dispose() {
    _disposed = true;
    _replaySuspended = true;
    _generation++;
    _timer?.cancel();
    _timer = null;
  }
}

/// Owns the only raw IMU subscription for each wheel. Consumers subscribe to
/// the ordered sample stream, preventing duplicate parsing and replay writes.
class ImuSampleHub {
  ImuSampleHub(this._ref) {
    _ref.onDispose(dispose);
  }
  final Ref _ref;
  final _rawSubs = <WheelSide, StreamSubscription<List<int>>>{};
  final _channels = <WheelSide, BleNotificationChannel<List<int>>>{};
  final _controllers = <WheelSide, StreamController<HubSample>>{};
  final _recovery = <WheelSide, SampleRecoveryBuffer>{};
  final _deviceIds = <WheelSide, String>{};

  BleRepository get _ble => _ref.read(bleRepositoryProvider);

  Stream<HubSample> samples(WheelSide side) => _controller(side).stream;
  RecoveryMetrics metrics(WheelSide side) =>
      _recovery[side]?.metrics ?? const RecoveryMetrics();

  Future<void> suspendReplay(WheelSide side) async {
    await _recovery[side]?.suspendReplay();
  }

  Future<void> start(WheelSide side) async {
    if (_rawSubs.containsKey(side)) return;
    final conn = _ref.read(connectionManagerProvider).bySide[side]!;
    final deviceId = conn.deviceId;
    final info = conn.info;
    if (deviceId == null || info == null) {
      throw StateError('$side not connected');
    }
    // A replay request adds control traffic and retransmitted notifications.
    // That is useful for a single wheel, but with two simultaneous 100 Hz
    // streams it can turn one transient Android scheduling gap into sustained
    // BLE backpressure. BLE itself already retransmits link-layer packets, so
    // disable application-level replay as soon as a second stream joins. Any
    // real sequence loss is still counted and the recording quality gate will
    // quarantine the session instead of amplifying congestion.
    final dualWheel = _rawSubs.isNotEmpty;
    if (dualWheel) {
      await Future.wait(
        _recovery.values.map((buffer) => buffer.suspendReplay()),
      );
    }
    final recovery = SampleRecoveryBuffer(
      replaySupported: info.supportsSampleReplay && !dualWheel,
      onSample: _controller(side).add,
      onReplay: (start, count) => _ble.writeControl(
        deviceId,
        ControlCommand.replayRange(startSeq: start, count: count),
      ),
    );
    _recovery[side] = recovery;
    _deviceIds[side] = deviceId;
    _ref.read(connectionManagerProvider.notifier).setAcquiring(deviceId, true);
    final channel = _ble.imuNotifications(deviceId);
    _channels[side] = channel;
    _rawSubs[side] = channel.stream.listen((bytes) {
      try {
        final now = DateTime.now().millisecondsSinceEpoch;
        for (final sample in ImuPacketParser.parseBatch(bytes)) {
          recovery.add(sample, now);
        }
      } on Object catch (error, stackTrace) {
        _controller(side).addError(error, stackTrace);
      }
    }, onError: _controller(side).addError);
    try {
      await channel.ready;
    } on Object {
      await _rawSubs.remove(side)?.cancel();
      _channels.remove(side);
      recovery.dispose();
      _recovery.remove(side);
      _deviceIds.remove(side);
      _ref
          .read(connectionManagerProvider.notifier)
          .setAcquiring(deviceId, false);
      rethrow;
    }
  }

  Future<void> stop(WheelSide side) async {
    final deviceId = _deviceIds.remove(side);
    await _rawSubs.remove(side)?.cancel();
    await _channels.remove(side)?.close();
    _recovery.remove(side)?.dispose();
    if (deviceId != null && _ref.mounted) {
      _ref
          .read(connectionManagerProvider.notifier)
          .setAcquiring(deviceId, false);
    }
  }

  StreamController<HubSample> _controller(WheelSide side) =>
      _controllers.putIfAbsent(
        side,
        // Downstream recording and presentation consumers must not execute
        // inside the raw notification callback. Queueing them asynchronously
        // lets Android deliver the other wheel before Dart performs UI work.
        () => StreamController<HubSample>.broadcast(),
      );

  void dispose() {
    for (final sub in _rawSubs.values) {
      unawaited(sub.cancel());
    }
    for (final channel in _channels.values) {
      unawaited(channel.close());
    }
    for (final recovery in _recovery.values) {
      recovery.dispose();
    }
    for (final controller in _controllers.values) {
      unawaited(controller.close());
    }
  }
}

final imuSampleHubProvider = Provider<ImuSampleHub>(ImuSampleHub.new);
