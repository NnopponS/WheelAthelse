import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wheelathlete/ble/ble_repository.dart';
import 'package:wheelathlete/ble/control_command.dart';
import 'package:wheelathlete/ble/imu_batch_processor.dart';
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
    this.notificationQueueHighWater = 0,
    this.notificationQueueOverflowFaults = 0,
    this.malformedPackets = 0,
  });
  final int recoveredSamples;
  final int unrecoveredSamples;
  final int replayAttempts;
  final int replayWriteFailures;
  final int notificationQueueHighWater;
  final int notificationQueueOverflowFaults;
  final int malformedPackets;
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

class HostIngressOverflowException implements Exception {
  const HostIngressOverflowException(this.capacity);
  final int capacity;
  @override
  String toString() =>
      'Host IMU notification queue reached capacity $capacity; unread data was not overwritten';
}

class NotificationIngressMetrics {
  const NotificationIngressMetrics({
    this.notificationsReceived = 0,
    this.queueHighWater = 0,
    this.queueOverflowFaults = 0,
    this.malformedPackets = 0,
  });

  final int notificationsReceived;
  final int queueHighWater;
  final int queueOverflowFaults;
  final int malformedPackets;
}

class _RawNotificationEnvelope {
  const _RawNotificationEnvelope(this.bytes, this.receivedAtMs);
  final Uint8List bytes;
  final int receivedAtMs;
}

/// Dart equivalent of the Windows `BoardIngestor`: BLE callback work is
/// bounded to an immutable copy + queue insertion. Parsing runs later, in
/// order, through a long-lived processor (an isolate in production).
class RawNotificationIngestor {
  RawNotificationIngestor({
    required this.processor,
    required this.onBatch,
    required this.onError,
    this.capacity = 512,
  }) {
    if (capacity < 1) throw ArgumentError.value(capacity, 'capacity');
  }

  final ImuBatchProcessor processor;
  final void Function(ProcessedImuBatch batch, int receivedAtMs) onBatch;
  final void Function(Object error, StackTrace stackTrace) onError;
  final int capacity;
  final ListQueue<_RawNotificationEnvelope> _queue = ListQueue();

  int _notificationsReceived = 0;
  int _queueHighWater = 0;
  int _queueOverflowFaults = 0;
  int _malformedPackets = 0;
  bool _draining = false;
  bool _disposed = false;
  Completer<void>? _idleWaiter;

  NotificationIngressMetrics get metrics => NotificationIngressMetrics(
    notificationsReceived: _notificationsReceived,
    queueHighWater: _queueHighWater,
    queueOverflowFaults: _queueOverflowFaults,
    malformedPackets: _malformedPackets,
  );

  bool enqueue(List<int> bytes, int receivedAtMs) {
    if (_disposed) return false;
    if (_queue.length >= capacity) {
      _queueOverflowFaults++;
      onError(HostIngressOverflowException(capacity), StackTrace.current);
      return false;
    }
    _notificationsReceived++;
    _queue.add(
      _RawNotificationEnvelope(Uint8List.fromList(bytes), receivedAtMs),
    );
    if (_queue.length > _queueHighWater) _queueHighWater = _queue.length;
    _scheduleDrain();
    return true;
  }

  void _scheduleDrain() {
    if (_draining || _disposed) return;
    _draining = true;
    scheduleMicrotask(() => unawaited(_drain()));
  }

  Future<void> _drain() async {
    try {
      while (_queue.isNotEmpty && !_disposed) {
        final envelope = _queue.removeFirst();
        try {
          final batch = await processor.parse(envelope.bytes);
          onBatch(batch, envelope.receivedAtMs);
        } on Object catch (error, stackTrace) {
          _malformedPackets++;
          onError(error, stackTrace);
        }
      }
    } finally {
      _draining = false;
      if (_queue.isEmpty) {
        final waiter = _idleWaiter;
        _idleWaiter = null;
        if (waiter != null && !waiter.isCompleted) waiter.complete();
      } else if (!_disposed) {
        _scheduleDrain();
      }
    }
  }

  Future<void> join() {
    if (_queue.isEmpty && !_draining) return Future<void>.value();
    return (_idleWaiter ??= Completer<void>()).future;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    await join();
    _disposed = true;
    await processor.dispose();
  }
}

final imuBatchProcessorFactoryProvider = Provider<ImuBatchProcessorFactory>(
  (ref) => IsolateImuBatchProcessor.new,
);

final imuIngressQueueCapacityProvider = Provider<int>((ref) => 512);

/// Owns the only raw IMU subscription for each wheel. Consumers subscribe to
/// the ordered sample stream, preventing duplicate parsing and replay writes.
class ImuSampleHub {
  ImuSampleHub(this._ref) {
    _ref.onDispose(() => unawaited(dispose()));
  }
  final Ref _ref;
  final _rawSubs = <WheelSide, StreamSubscription<List<int>>>{};
  final _channels = <WheelSide, BleNotificationChannel<List<int>>>{};
  final _controllers = <WheelSide, StreamController<HubSample>>{};
  final _recovery = <WheelSide, SampleRecoveryBuffer>{};
  final _ingress = <WheelSide, RawNotificationIngestor>{};
  final _deviceIds = <WheelSide, String>{};

  BleRepository get _ble => _ref.read(bleRepositoryProvider);

  Stream<HubSample> samples(WheelSide side) => _controller(side).stream;

  RecoveryMetrics metrics(WheelSide side) {
    final recovery = _recovery[side]?.metrics ?? const RecoveryMetrics();
    final ingress =
        _ingress[side]?.metrics ?? const NotificationIngressMetrics();
    return RecoveryMetrics(
      recoveredSamples: recovery.recoveredSamples,
      unrecoveredSamples: recovery.unrecoveredSamples,
      replayAttempts: recovery.replayAttempts,
      replayWriteFailures: recovery.replayWriteFailures,
      notificationQueueHighWater: ingress.queueHighWater,
      notificationQueueOverflowFaults: ingress.queueOverflowFaults,
      malformedPackets: ingress.malformedPackets,
    );
  }

  Future<void> suspendReplay(WheelSide side) async {
    await _recovery[side]?.suspendReplay();
  }

  /// Wait until every raw notification accepted so far for [side] has been
  /// parsed and published to hub consumers.
  Future<void> join(WheelSide side) =>
      _ingress[side]?.join() ?? Future<void>.value();

  Future<void> start(WheelSide side) async {
    if (_rawSubs.containsKey(side)) return;
    final conn = _ref.read(connectionManagerProvider).bySide[side]!;
    final deviceId = conn.deviceId;
    final info = conn.info;
    if (deviceId == null || info == null) {
      throw StateError('$side not connected');
    }

    // Match the PC app under dual-wheel load: prioritize one bounded live
    // ingress path over adding application-level replay traffic. Single-wheel
    // sessions can still use firmware replay.
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
    final processor = _ref.read(imuBatchProcessorFactoryProvider)(info);
    final ingress = RawNotificationIngestor(
      processor: processor,
      capacity: _ref.read(imuIngressQueueCapacityProvider),
      onBatch: (batch, receivedAtMs) {
        for (final sample in batch.samples) {
          recovery.add(sample, receivedAtMs);
        }
      },
      onError: (error, stackTrace) {
        final controller = _controllers[side];
        if (controller != null && !controller.isClosed) {
          controller.addError(error, stackTrace);
        }
      },
    );

    _recovery[side] = recovery;
    _ingress[side] = ingress;
    _deviceIds[side] = deviceId;
    _ref.read(connectionManagerProvider.notifier).setAcquiring(deviceId, true);
    final channel = _ble.imuNotifications(deviceId);
    _channels[side] = channel;
    _rawSubs[side] = channel.stream.listen((bytes) {
      // Keep this BLE callback intentionally tiny. No parsing, unit
      // conversion, disk I/O, chart work, or replay decisions occur here.
      ingress.enqueue(bytes, DateTime.now().millisecondsSinceEpoch);
    }, onError: _controller(side).addError);
    try {
      await channel.ready;
    } on Object {
      await _rawSubs.remove(side)?.cancel();
      _channels.remove(side);
      await ingress.dispose();
      _ingress.remove(side);
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
    final ingress = _ingress.remove(side);
    if (ingress != null) {
      // Same contract as PC engine.join(): all notifications accepted by the
      // callback finish parsing before local stream ownership is released.
      await ingress.join();
      await ingress.dispose();
    }
    await _channels.remove(side)?.close();
    _recovery.remove(side)?.dispose();
    if (deviceId != null && _ref.mounted) {
      _ref
          .read(connectionManagerProvider.notifier)
          .setAcquiring(deviceId, false);
    }
  }

  StreamController<HubSample> _controller(WheelSide side) => _controllers
      .putIfAbsent(side, () => StreamController<HubSample>.broadcast());

  Future<void> dispose() async {
    final rawSubs = _rawSubs.values.toList(growable: false);
    _rawSubs.clear();
    await Future.wait(rawSubs.map((sub) => sub.cancel()));

    final ingresses = _ingress.values.toList(growable: false);
    _ingress.clear();
    await Future.wait(ingresses.map((ingress) => ingress.dispose()));

    final channels = _channels.values.toList(growable: false);
    _channels.clear();
    await Future.wait(channels.map((channel) => channel.close()));

    for (final recovery in _recovery.values) {
      recovery.dispose();
    }
    _recovery.clear();

    final controllers = _controllers.values.toList(growable: false);
    _controllers.clear();
    await Future.wait(controllers.map((controller) => controller.close()));
  }
}

final imuSampleHubProvider = Provider<ImuSampleHub>(ImuSampleHub.new);
