import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wheelathlete/ble/imu_packet.dart';
import 'package:wheelathlete/ble/sync_packet.dart';
import 'package:wheelathlete/records/session_model.dart';
import 'package:wheelathlete/state/ble_providers.dart';
import 'package:wheelathlete/state/browse_providers.dart';
import 'package:wheelathlete/state/imu_providers.dart';
import 'package:wheelathlete/state/sample_hub.dart';
import 'package:wheelathlete/state/session_timeline.dart';
import 'package:wheelathlete/state/sync_providers.dart';
import 'package:wheelathlete/theme/theme.dart';
import 'package:wheelathlete/widgets/connection_card.dart';

/// Recording state machine status.
enum RecordingStatus {
  idle,
  arming,
  awaitingSamples,
  recording,
  stopping,
  stopped,
  failed,
}

class RecordingWheelHealth {
  const RecordingWheelHealth({
    this.receivedCount = 0,
    this.effectiveRateHz = 0,
    this.lastSampleAgeMs,
    this.recoveredSamples = 0,
    this.unrecoveredSamples = 0,
    this.firmwareProduced = 0,
    this.firmwareNotified = 0,
    this.queueDrops = 0,
    this.fifoFaults = 0,
    this.fifoDroppedSamples = 0,
    this.transportFailures = 0,
    this.queueDepth = 0,
    this.stalled = false,
  });

  final int receivedCount;
  final double effectiveRateHz;
  final int? lastSampleAgeMs;
  final int recoveredSamples;
  final int unrecoveredSamples;
  final int firmwareProduced;
  final int firmwareNotified;
  final int queueDrops;
  final int fifoFaults;
  final int fifoDroppedSamples;
  final int transportFailures;
  final int queueDepth;
  final bool stalled;
}

enum AcquisitionFailureCause {
  sampleQueueOverflow,
  imuFifoFault,
  bleTransportCongestion,
}

/// Classifies loss at its source so queue overflow, sensor FIFO faults, and
/// BLE congestion are never presented as the same failure.
AcquisitionFailureCause? criticalAcquisitionFailure(AcqHealthEvent health) {
  if (health.fifoFaults > 0 || health.fifoDroppedSamples > 0) {
    return AcquisitionFailureCause.imuFifoFault;
  }
  if (health.queueDrops > 0) {
    return AcquisitionFailureCause.sampleQueueOverflow;
  }
  if (health.transportFailures >= 3 && health.queueDepth >= 64) {
    return AcquisitionFailureCause.bleTransportCongestion;
  }
  return null;
}

/// Backward-compatible predicate used by existing recording safety tests.
bool isCriticalTransportHealth(AcqHealthEvent health) =>
    criticalAcquisitionFailure(health) != null;

/// Whole recording state surfaced to the UI.
class RecordingState {
  const RecordingState({
    this.status = RecordingStatus.idle,
    this.config,
    this.startTime,
    this.sampleCount = 0,
    this.savedSessionId,
    this.lastMeta,
    this.healthBySide = const {},
    this.error,
  });

  final RecordingStatus status;
  final SessionConfig? config;
  final DateTime? startTime;
  final int sampleCount;
  final String? savedSessionId;

  /// The [SessionMeta] of the most recently stopped session. Set when
  /// [RecordingNotifier.stopRecording] completes and cleared on [reset].
  /// Used by the stopped view's Preview button to open [SessionPreviewPage]
  /// without re-reading from disk.
  final SessionMeta? lastMeta;

  final Map<WheelSide, RecordingWheelHealth> healthBySide;

  final String? error;

  RecordingState copyWith({
    RecordingStatus? status,
    SessionConfig? config,
    DateTime? startTime,
    int? sampleCount,
    Object? savedSessionId = _unset,
    Object? lastMeta = _unset,
    Map<WheelSide, RecordingWheelHealth>? healthBySide,
    Object? error = _unset,
  }) => RecordingState(
    status: status ?? this.status,
    config: config ?? this.config,
    startTime: startTime ?? this.startTime,
    sampleCount: sampleCount ?? this.sampleCount,
    savedSessionId: identical(savedSessionId, _unset)
        ? this.savedSessionId
        : savedSessionId as String?,
    lastMeta: identical(lastMeta, _unset)
        ? this.lastMeta
        : lastMeta as SessionMeta?,
    healthBySide: healthBySide ?? this.healthBySide,
    error: identical(error, _unset) ? this.error : error as String?,
  );

  static const Object _unset = Object();
}

/// Orchestrates a recording session: start/stop IMU streaming on both wheels,
/// buffer samples with synced timestamps, and save the session (meta +
/// samples) to the storage repository on stop.
///
/// State machine:
/// - idle → startRecording → recording (streams IMU, buffers samples)
/// - recording → stopRecording → stopped (saves to storage, stops streams)
/// - stopped → reset → idle (clears state for next session)
///
/// The Mark Event function was removed in Phase 3 (D16) — IMU data is now
/// synced with camera video in post-processing. The CSV `marker` column is
/// kept for backward compatibility but is always `0`/`false` for new
/// recordings ([BufferedSample.marker] defaults to `false`).
class RecordingNotifier extends Notifier<RecordingState> {
  final _buffer = <BufferedSample>[];
  final _subs = <WheelSide, StreamSubscription<HubSample>>{};
  final _trackers = <WheelSide, ImuSeqTracker>{};
  final _receivedBySide = <WheelSide, int>{};
  final _lastSampleAtMs = <WheelSide, int>{};
  final _firstSampleSides = <WheelSide>{};
  final _expectedSides = <WheelSide>{};
  final _healthAtStart = <WheelSide, AcqHealthEvent?>{};
  Timer? _firstSampleTimer;
  Timer? _healthTimer;
  bool _stallAbortStarted = false;
  String? _forcedDegradation;

  /// Periodic timer for continuous sync refinement during recording.
  /// Sends SYNC_PINGs to both wheels every few seconds so the drift fit
  /// stays accurate over long recordings (corrects crystal drift).
  Timer? _continuousSyncTimer;

  /// True when a throttled state emission is pending. The buffer always
  /// accumulates every sample immediately; only the `state =` assignment
  /// is deferred to the next emit interval tick.
  bool _emitPending = false;
  Timer? _emitTimer;

  @override
  RecordingState build() {
    ref.onDispose(() {
      for (final s in _subs.values) {
        s.cancel();
      }
      _subs.clear();
      _trackers.clear();
      _buffer.clear();
      _continuousSyncTimer?.cancel();
      _emitTimer?.cancel();
      _firstSampleTimer?.cancel();
      _healthTimer?.cancel();
    });
    return const RecordingState();
  }

  /// Pre-arms IMU streaming for every currently connected wheel: enables BLE
  /// notify and subscribes the buffering listener, without starting a
  /// recording session (state stays idle).
  ///
  /// Call this as early as possible — e.g. at the very start of the
  /// countdown flow, well before the scheduled START command is sent — so
  /// the app is already listening by the time the firmware begins pushing
  /// samples at the synchronized start instant. The firmware only sends IMU
  /// notifications while acquisition is running (gated by the START/STOP
  /// protocol commands), so arming early never buffers stray samples.
  ///
  /// Previously, IMU streaming was only subscribed to *after* START_FIRED —
  /// i.e. after the firmware had already begun streaming — which raced the
  /// async BLE "enable notify" round trip against incoming data and dropped
  /// the first several samples of every recording. Arming during the
  /// countdown (with seconds of margin) eliminates that race.
  ///
  /// Idempotent — sides that are already armed (have an active subscription)
  /// are left untouched.
  ///
  /// Both wheels are armed in parallel (Future.wait) so the BLE stack sets
  /// up both notification channels concurrently. Sequential arming causes
  /// the second wheel's setNotifyValue to race with the first wheel's
  /// active stream, leading to packet drops on the second board.
  Future<void> armStreaming() async {
    if (_subs.isEmpty) {
      _buffer.clear();
      _receivedBySide.clear();
      _lastSampleAtMs.clear();
      _firstSampleSides.clear();
      _expectedSides.clear();
      if (state.status == RecordingStatus.idle) {
        state = state.copyWith(status: RecordingStatus.arming, error: null);
      }
    }
    final imuNotifier = ref.read(imuStreamProvider.notifier);
    final connState = ref.read(connectionManagerProvider);
    final sidesToArm = <WheelSide>[];
    final futures = <Future<void>>[];
    for (final side in WheelSide.values) {
      if (_subs.containsKey(side)) continue; // already armed
      final conn = connState.bySide[side]!;
      if (conn.status == ConnectionStatus.connected && conn.deviceId != null) {
        sidesToArm.add(side);
        futures.add(
          (() async {
            // The lossless recording consumer must be registered before the
            // presentation consumer opens the raw BLE channel. Some BLE
            // stacks synchronously replay lastValue on subscription.
            await _subscribeImu(side);
            await imuNotifier.start(side);
          })(),
        );
      }
    }
    await Future.wait(futures);
    // Prepare each newly armed link exactly once, after its notification
    // channel is ready and before countdown/START. A later startRecording()
    // call sees the existing subscriptions and must not renegotiate either
    // Android BLE link while START_FIRED samples are already flowing.
    final connAfterArm = ref.read(connectionManagerProvider);
    await Future.wait(
      sidesToArm.map((side) {
        final deviceId = connAfterArm.bySide[side]!.deviceId;
        return deviceId == null
            ? Future<void>.value()
            : ref.read(bleRepositoryProvider).prepareForStreaming(deviceId);
      }),
    );
    if (state.status == RecordingStatus.arming) {
      state = state.copyWith(status: RecordingStatus.idle);
    }
  }

  /// Cancels any pre-armed IMU subscriptions without recording anything.
  /// Used when a countdown is aborted before recording actually begins.
  /// No-op while actively recording.
  Future<void> disarmStreaming() async {
    if (state.status == RecordingStatus.recording ||
        state.status == RecordingStatus.awaitingSamples) {
      return;
    }
    _stopContinuousSync();
    final imuNotifier = ref.read(imuStreamProvider.notifier);
    // Stop both wheels in parallel.
    final stopFutures = _subs.keys
        .map((side) => imuNotifier.stop(side))
        .toList();
    await Future.wait(stopFutures);
    for (final s in _subs.values) {
      await s.cancel();
    }
    _subs.clear();
    _buffer.clear();
    _firstSampleTimer?.cancel();
    _healthTimer?.cancel();
  }

  /// Starts a recording session with the given [config].
  ///
  /// Both wheels must already be connected. Arms IMU streaming for any
  /// connected side not already armed by [armStreaming] and subscribes to
  /// buffer samples. Throws if already recording.
  Future<void> startRecording(SessionConfig config) async {
    if (state.status == RecordingStatus.recording ||
        state.status == RecordingStatus.awaitingSamples ||
        state.status == RecordingStatus.arming ||
        state.status == RecordingStatus.stopping) {
      throw StateError('Recording operation already in progress');
    }

    final startTime = config.startTime ?? DateTime.now();
    final configWithStart = SessionConfig(
      topic: config.topic,
      trialNumber: config.trialNumber,
      sampleRateHz: config.sampleRateHz,
      athleteName: config.athleteName,
      notes: config.notes,
      utcStartMs: config.utcStartMs,
      utcOffsetMs: config.utcOffsetMs,
      protocolTemplateId: config.protocolTemplateId,
      startTime: startTime,
    );

    // Normally a no-op — the countdown flow already calls [armStreaming]
    // well before this point — but kept here so startRecording remains safe
    // to call directly (e.g. tests, or a future immediate-start path).
    state = state.copyWith(status: RecordingStatus.arming, error: null);
    await armStreaming();
    _expectedSides
      ..clear()
      ..addAll(_subs.keys);
    final healthSnapshot = ref.read(syncEngineProvider);
    _healthAtStart
      ..clear()
      ..addEntries(
        _expectedSides.map(
          (side) => MapEntry(side, healthSnapshot.bySide[side]!.acqHealth),
        ),
      );

    final scheduled = config.utcStartMs != null;
    if (scheduled) {
      final syncState = ref.read(syncEngineProvider);
      final missingAcks = _expectedSides
          .where((side) => syncState.bySide[side]!.lastStartFiredUs == null)
          .toList(growable: false);
      if (missingAcks.isNotEmpty) {
        await _failBeforeSamples(
          'START acknowledgement missing from '
          '${missingAcks.map(_sideLabel).join(', ')}. Reconnect that wheel and retry.',
        );
        throw StateError(state.error ?? 'START acknowledgement missing');
      }
    }

    state = RecordingState(
      status: scheduled
          ? RecordingStatus.awaitingSamples
          : RecordingStatus.recording,
      config: configWithStart,
      startTime: startTime,
      sampleCount: _buffer.length,
    );

    _startHealthMonitor();
    if (scheduled) {
      _promoteWhenFirstSamplesReady();
      if (state.status == RecordingStatus.awaitingSamples) {
        _firstSampleTimer?.cancel();
        _firstSampleTimer = Timer(
          ref.read(firstSampleTimeoutProvider),
          () => unawaited(_failMissingFirstSamples()),
        );
      }
    }

    // Do not inject control-point GATT traffic while two 100 Hz notification
    // streams are active. On Android the write to the second peripheral can
    // stall its notification delivery for almost two seconds, creating the
    // queue growth and drops seen on the right wheel. The startup sync burst
    // already supplies the paired clock fit; periodic refinement remains
    // available for lower-bandwidth single-wheel recordings.
    if (_expectedSides.length == 1) {
      _startContinuousSync();
    }
  }

  /// Interval between continuous sync pings during recording.
  static const _continuousSyncInterval = Duration(seconds: 10);

  static String _sideLabel(WheelSide side) =>
      side == WheelSide.left ? 'left wheel' : 'right wheel';

  void _promoteWhenFirstSamplesReady() {
    if (state.status != RecordingStatus.awaitingSamples) return;
    if (!_expectedSides.every(_firstSampleSides.contains)) return;
    _firstSampleTimer?.cancel();
    _firstSampleTimer = null;
    state = state.copyWith(status: RecordingStatus.recording);
  }

  Future<void> _failMissingFirstSamples() async {
    if (!ref.mounted || state.status != RecordingStatus.awaitingSamples) {
      return;
    }
    final missing = _expectedSides
        .where((side) => !_firstSampleSides.contains(side))
        .toList(growable: false);
    if (missing.isEmpty) {
      _promoteWhenFirstSamplesReady();
      return;
    }
    await _failBeforeSamples(
      'No samples from ${missing.map(_sideLabel).join(', ')} within 2 seconds. '
      'Check its connection and battery, then retry.',
    );
  }

  Future<void> _failBeforeSamples(String message) async {
    _firstSampleTimer?.cancel();
    _stopContinuousSync();
    _healthTimer?.cancel();
    final sides = _subs.keys.toList(growable: false);
    final sync = ref.read(syncEngineProvider.notifier);
    await Future.wait(
      sides.map((side) async {
        try {
          await sync.sendStop(side);
        } on Object {
          // Best effort rollback; the actionable failure is retained below.
        }
      }),
    );
    final imu = ref.read(imuStreamProvider.notifier);
    await Future.wait(sides.map(imu.stop));
    for (final subscription in _subs.values.toList(growable: false)) {
      await subscription.cancel();
    }
    _subs.clear();
    _buffer.clear();
    state = RecordingState(status: RecordingStatus.failed, error: message);
  }

  void _startHealthMonitor() {
    _healthTimer?.cancel();
    _stallAbortStarted = false;
    _healthTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!ref.mounted ||
          (state.status != RecordingStatus.recording &&
              state.status != RecordingStatus.awaitingSamples)) {
        return;
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      final started = state.startTime?.millisecondsSinceEpoch ?? now;
      final elapsedSeconds = ((now - started).clamp(1, 1 << 31)) / 1000.0;
      final syncState = ref.read(syncEngineProvider);
      final hub = ref.read(imuSampleHubProvider);
      final health = <WheelSide, RecordingWheelHealth>{};
      WheelSide? stalledSide;
      WheelSide? failedSide;
      AcquisitionFailureCause? failureCause;
      for (final side in _expectedSides) {
        final last = _lastSampleAtMs[side];
        final validLast = (last != null && last >= started) ? last : null;
        final age = validLast == null ? (now - started) : (now - validLast);
        final recovery = hub.metrics(side);
        final firmware = syncState.bySide[side]!.acqHealth;
        final freshFirmwareHealth =
            firmware != null && !identical(firmware, _healthAtStart[side]);
        final currentFailure = freshFirmwareHealth
            ? criticalAcquisitionFailure(firmware)
            : null;
        if (currentFailure != null && failedSide == null) {
          failedSide = side;
          failureCause = currentFailure;
        }
        final stalled = age >= 1000;
        if (age >= 3000) stalledSide ??= side;
        health[side] = RecordingWheelHealth(
          receivedCount: _receivedBySide[side] ?? 0,
          effectiveRateHz: (_receivedBySide[side] ?? 0) / elapsedSeconds,
          lastSampleAgeMs: age,
          recoveredSamples: recovery.recoveredSamples,
          unrecoveredSamples: recovery.unrecoveredSamples,
          firmwareProduced: firmware?.producedSamples ?? 0,
          firmwareNotified: firmware?.notifiedSamples ?? 0,
          queueDrops: firmware?.queueDrops ?? syncState.bySide[side]!.dropCount,
          fifoFaults: firmware?.fifoFaults ?? 0,
          fifoDroppedSamples: firmware?.fifoDroppedSamples ?? 0,
          transportFailures: firmware?.transportFailures ?? 0,
          queueDepth: firmware?.queueDepth ?? 0,
          stalled: stalled,
        );
      }
      state = state.copyWith(healthBySide: health);
      if (failedSide != null && failureCause != null && !_stallAbortStarted) {
        _stallAbortStarted = true;
        unawaited(_abortForAcquisitionHealth(failedSide, failureCause));
      } else if (stalledSide != null &&
          state.status == RecordingStatus.recording &&
          !_stallAbortStarted) {
        _stallAbortStarted = true;
        unawaited(_abortForStall(stalledSide));
      }
    });
  }

  Future<void> _abortForAcquisitionHealth(
    WheelSide side,
    AcquisitionFailureCause cause,
  ) async {
    final firmware = ref.read(syncEngineProvider).bySide[side]!.acqHealth;
    _forcedDegradation = switch (cause) {
      AcquisitionFailureCause.sampleQueueOverflow =>
        '${_sideLabel(side)} sample queue overflow '
            '(drops ${firmware?.queueDrops ?? 0}, '
            'depth ${firmware?.queueDepth ?? 0})',
      AcquisitionFailureCause.imuFifoFault =>
        '${_sideLabel(side)} IMU FIFO fault '
            '(faults ${firmware?.fifoFaults ?? 0}, '
            'lost samples ${firmware?.fifoDroppedSamples ?? 0})',
      AcquisitionFailureCause.bleTransportCongestion =>
        '${_sideLabel(side)} BLE transport congested '
            '(queue ${firmware?.queueDepth ?? 0}, '
            'failures ${firmware?.transportFailures ?? 0})',
    };
    try {
      await stopRecording();
      if (ref.mounted) {
        state = state.copyWith(
          status: RecordingStatus.failed,
          error:
              'Recording stopped: $_forcedDegradation. '
              'Reconnect both wheels and retry; partial data was quarantined.',
        );
      }
    } on Object catch (error) {
      if (ref.mounted) {
        state = state.copyWith(
          status: RecordingStatus.failed,
          error: 'Acquisition recovery failed: $error',
        );
      }
    }
  }

  Future<void> _abortForStall(WheelSide side) async {
    _forcedDegradation = '${_sideLabel(side)} stalled for at least 3 seconds';
    try {
      await stopRecording();
      if (ref.mounted) {
        state = state.copyWith(
          status: RecordingStatus.failed,
          error: 'Recording stopped: $_forcedDegradation. Trial quarantined.',
        );
      }
    } on Object catch (error) {
      if (ref.mounted) {
        state = state.copyWith(
          status: RecordingStatus.failed,
          error: 'Recording abort failed: $error',
        );
      }
    }
  }

  void _startContinuousSync() {
    _continuousSyncTimer?.cancel();
    _continuousSyncTimer = Timer.periodic(_continuousSyncInterval, (_) {
      if (!ref.mounted ||
          (state.status != RecordingStatus.recording &&
              state.status != RecordingStatus.awaitingSamples)) {
        _continuousSyncTimer?.cancel();
        return;
      }
      final sync = ref.read(syncEngineProvider.notifier);
      final connState = ref.read(connectionManagerProvider);
      // Ping all connected wheels in parallel.
      final futures = <Future<void>>[];
      for (final side in WheelSide.values) {
        if (connState.bySide[side]!.status == ConnectionStatus.connected &&
            connState.bySide[side]!.deviceId != null) {
          futures.add(sync.sendPing(side));
        }
      }
      unawaited(
        Future.wait(futures).then<void>(
          (_) {},
          onError: (Object _, StackTrace _) {
            // Periodic clock refinement is best effort. A transient GATT
            // rejection must not escape the timer zone or abort recording.
          },
        ),
      );
    });
  }

  void _stopContinuousSync() {
    _continuousSyncTimer?.cancel();
    _continuousSyncTimer = null;
  }

  Future<void> _subscribeImu(WheelSide side) async {
    final conn = ref.read(connectionManagerProvider).bySide[side]!;
    final deviceId = conn.deviceId;
    final info = conn.info;
    if (deviceId == null || info == null) return;

    _trackers[side] = ImuSeqTracker();

    final hub = ref.read(imuSampleHubProvider);
    final subscription = hub
        .samples(side)
        .listen(
          (event) {
            try {
              final tracker = _trackers[side]!;
              final sample = event.sample;
              tracker.gapCount(sample.seq);

              final wheelSync = ref.read(syncEngineProvider).bySide[side]!;
              final reading = sample.toReading(info);
              final startUs = wheelSync.lastStartFiredUs;
              final syncedMs = startUs == null
                  ? sample.tDeviceUs / 1000.0
                  : SessionTimeline.relativeUs(
                          timestampUs: sample.tDeviceUs,
                          startUs: startUs,
                          driftFit: wheelSync.driftFit,
                        ) /
                        1000.0;
              _buffer.add(
                BufferedSample(
                  reading: reading,
                  wheel: side,
                  timestampAppMs: event.receivedAtMs,
                  timestampSyncedMs: syncedMs,
                ),
              );
              _receivedBySide[side] = (_receivedBySide[side] ?? 0) + 1;
              _lastSampleAtMs[side] = event.receivedAtMs;
              _firstSampleSides.add(side);

              if (!ref.mounted) return;
              _promoteWhenFirstSamplesReady();
              if (state.status != RecordingStatus.idle &&
                  state.status != RecordingStatus.arming) {
                _emitSampleCount();
              }
            } on Object catch (e) {
              if (!ref.mounted) return;
              _flushEmit();
              state = state.copyWith(error: 'IMU buffer error: $e');
            }
          },
          onError: (Object e) {
            if (!ref.mounted) return;
            _flushEmit();
            state = state.copyWith(error: 'IMU stream error: $e');
          },
        );
    _subs[side] = subscription;
    try {
      await hub.start(side);
    } on Object {
      await _subs.remove(side)?.cancel();
      _trackers.remove(side);
      rethrow;
    }
  }

  /// Emits `sampleCount` to state, either immediately (when the emit interval
  /// is zero — the test default) or deferred to the next interval tick. The
  /// buffer always has all samples; only the state emission is throttled to
  /// avoid flooding the UI with rebuilds during two-board 100 Hz streaming.
  void _emitSampleCount() {
    final interval = ref.read(recordingEmitIntervalProvider);
    if (interval == Duration.zero) {
      _emitPending = false;
      _emitTimer?.cancel();
      _emitTimer = null;
      state = state.copyWith(sampleCount: _buffer.length);
      return;
    }
    _emitPending = true;
    _emitTimer ??= Timer(interval, _flushEmit);
  }

  /// Flushes any pending throttled emission immediately.
  void _flushEmit() {
    _emitTimer?.cancel();
    _emitTimer = null;
    if (_emitPending && ref.mounted) {
      _emitPending = false;
      state = state.copyWith(sampleCount: _buffer.length);
    }
  }

  Future<void> _disconnectRecordingSideForSafety({
    required WheelSide side,
    required ConnectionManagerNotifier connectionManager,
    required List<String> stopErrors,
  }) async {
    try {
      await connectionManager.disconnect(side);
      stopErrors.add('${side.name}: STOP failed; disconnected for safety');
    } on Object catch (error) {
      stopErrors.add('${side.name}: STOP and safety disconnect failed: $error');
      state = state.copyWith(
        status: RecordingStatus.failed,
        error: 'STOP warning: ${stopErrors.join('; ')}',
      );
      throw StateError(stopErrors.last);
    }
  }

  /// Stops the recording session, saves it to storage, and stops IMU
  /// streaming. Throws if not recording.
  Future<void> stopRecording() async {
    if (state.status == RecordingStatus.stopping) return;
    if (state.status == RecordingStatus.awaitingSamples) {
      state = state.copyWith(status: RecordingStatus.stopping);
      await _failBeforeSamples(
        'Recording stopped before every wheel delivered its first sample. '
        'Nothing was saved.',
      );
      return;
    }
    if (state.status != RecordingStatus.recording) {
      throw StateError('Not recording');
    }
    if (_buffer.isEmpty) {
      state = state.copyWith(status: RecordingStatus.stopping);
      await _failBeforeSamples(
        'Recording contained 0 samples. Check both wheel connections and retry.',
      );
      return;
    }
    state = state.copyWith(status: RecordingStatus.stopping);
    // Flush any pending throttled sampleCount so the final state is consistent
    // before we read _buffer.length for the session meta.
    _flushEmit();
    final config = state.config!;
    final startTime = state.startTime!;
    final endTime = DateTime.now();
    final durationMs =
        endTime.millisecondsSinceEpoch - startTime.millisecondsSinceEpoch;

    // Stop continuous sync refinement.
    _stopContinuousSync();
    _firstSampleTimer?.cancel();
    _healthTimer?.cancel();

    // Ask firmware to stop acquisition and flush its final partial batch.
    // Keep IMU subscriptions alive until acknowledgements/final notifications
    // have had time to arrive.
    final syncNotifier = ref.read(syncEngineProvider.notifier);
    final stopSides = _subs.keys.toList(growable: false);
    final previousStopAcks = {
      for (final side in stopSides)
        side: ref.read(syncEngineProvider).bySide[side]!.lastStopFiredUs,
    };
    final stopErrors = <String>[];
    final acknowledgedStops = <WheelSide>{};
    final connectionManager = ref.read(connectionManagerProvider.notifier);
    final deviceIds = {
      for (final side in stopSides)
        side: ref.read(connectionManagerProvider).bySide[side]!.deviceId,
    };
    // Stop scheduling replay control writes before STOP enters each device's
    // serialized GATT queue. The IMU subscriptions remain alive for the final
    // drained samples and STOP_FIRED acknowledgement.
    final hub = ref.read(imuSampleHubProvider);
    await Future.wait(stopSides.map(hub.suspendReplay));
    // Serialize STOP across boards so Android does not have two control
    // writes competing with both high-rate notification streams.
    final writtenStops = <WheelSide>{};
    for (final side in stopSides) {
      final result = await syncNotifier.sendStopWithRetry(side);
      if (result.written) {
        writtenStops.add(side);
      } else {
        await _disconnectRecordingSideForSafety(
          side: side,
          connectionManager: connectionManager,
          stopErrors: stopErrors,
        );
      }
    }
    final stopResults = await Future.wait(
      writtenStops.map(
        (side) async => (
          side,
          await syncNotifier.waitForStop(
            side,
            previous: previousStopAcks[side],
            timeout: ref.read(recordingStopAckTimeoutProvider),
          ),
        ),
      ),
    );
    for (final (side, wasAcknowledged) in stopResults) {
      if (wasAcknowledged) {
        acknowledgedStops.add(side);
      } else {
        await _disconnectRecordingSideForSafety(
          side: side,
          connectionManager: connectionManager,
          stopErrors: stopErrors,
        );
      }
    }
    // A retained final batch may be in the bounded 100 ms congestion
    // backoff. Keep subscriptions alive long enough for one retry cycle.
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (stopErrors.isNotEmpty) {
      state = state.copyWith(error: 'STOP warning: ${stopErrors.join('; ')}');
    }
    final recoveryMetrics = {
      for (final side in stopSides)
        side: ref.read(imuSampleHubProvider).metrics(side),
    };

    // Stop IMU streaming on all sides in parallel.
    final imuNotifier = ref.read(imuStreamProvider.notifier);
    await Future.wait(_subs.keys.map((side) => imuNotifier.stop(side)));
    for (final s in _subs.values) {
      await s.cancel();
    }
    _subs.clear();
    for (final side in acknowledgedStops) {
      final deviceId = deviceIds[side];
      if (deviceId != null) connectionManager.setAcquiring(deviceId, false);
    }

    // Build session meta with sync quality from the sync engine.
    final syncState = ref.read(syncEngineProvider);
    _finalizeTimeline(syncState);
    final leftOffset = syncState.bySide[WheelSide.left]!.offset?.offsetUs;
    final rightOffset = syncState.bySide[WheelSide.right]!.offset?.offsetUs;
    final leftResidual =
        syncState.bySide[WheelSide.left]!.driftFit?.residualRmsMs;
    final rightResidual =
        syncState.bySide[WheelSide.right]!.driftFit?.residualRmsMs;

    final sessionId = config.sessionId;
    final meta = SessionMeta(
      sessionId: sessionId,
      topic: config.topic,
      trialNumber: config.trialNumber,
      athleteName: config.athleteName,
      sampleRateHz: config.sampleRateHz,
      startTime: startTime,
      durationMs: durationMs,
      sampleCount: _buffer.length,
      markerCount: 0,
      offsetUsLeft: leftOffset,
      offsetUsRight: rightOffset,
      driftResidualRmsMsLeft: leftResidual,
      driftResidualRmsMsRight: rightResidual,
      notes: config.notes,
      utcStartMs: config.utcStartMs,
      recordedSides: _trackers.keys
          .map((side) => side == WheelSide.left ? 'L' : 'R')
          .toList(growable: false),
      firmwareVersions: {
        for (final side in WheelSide.values)
          if (ref.read(connectionManagerProvider).bySide[side]!.info
              case final info?)
            (side == WheelSide.left ? 'L' : 'R'): info.fwVersion,
      },
      boardModels: {
        for (final side in WheelSide.values)
          if (ref.read(connectionManagerProvider).bySide[side]!.info
              case final info?)
            (side == WheelSide.left ? 'L' : 'R'): info.hardwareModel.label,
      },
      dropCounts: {
        'L': syncState.bySide[WheelSide.left]!.dropCount,
        'R': syncState.bySide[WheelSide.right]!.dropCount,
      },
      sampleQueueDrops: {
        for (final side in stopSides)
          side == WheelSide.left ? 'L' : 'R':
              syncState.bySide[side]!.acqHealth?.queueDrops ?? 0,
      },
      imuFifoFaults: {
        for (final side in stopSides)
          side == WheelSide.left ? 'L' : 'R':
              syncState.bySide[side]!.acqHealth?.fifoFaults ?? 0,
      },
      imuFifoDroppedSamples: {
        for (final side in stopSides)
          side == WheelSide.left ? 'L' : 'R':
              syncState.bySide[side]!.acqHealth?.fifoDroppedSamples ?? 0,
      },
      recoveredSamples: {
        for (final side in stopSides)
          side == WheelSide.left ? 'L' : 'R':
              recoveryMetrics[side]!.recoveredSamples,
      },
      unrecoveredSamples: {
        for (final side in stopSides)
          side == WheelSide.left ? 'L' : 'R':
              recoveryMetrics[side]!.unrecoveredSamples,
      },
      replayAttempts: {
        for (final side in stopSides)
          side == WheelSide.left ? 'L' : 'R':
              recoveryMetrics[side]!.replayAttempts,
      },
      degradationReason: _degradationReason(
        stopSides: stopSides,
        recoveryMetrics: recoveryMetrics,
        syncState: syncState,
      ),
      sequenceGaps: {
        for (final entry in _trackers.entries)
          (entry.key == WheelSide.left ? 'L' : 'R'): entry.value.totalGaps,
      },
      startAcknowledgedUs: {
        // ignore: use_null_aware_elements
        if (syncState.bySide[WheelSide.left]!.lastStartFiredUs
            case final value?)
          'L': value,
        // ignore: use_null_aware_elements
        if (syncState.bySide[WheelSide.right]!.lastStartFiredUs
            case final value?)
          'R': value,
      },
      startDeltaUs: _startDelta(syncState),
      transportFailures: {
        for (final side in stopSides)
          side == WheelSide.left ? 'L' : 'R':
              syncState.bySide[side]!.acqHealth?.transportFailures ?? 0,
      },
      firmwareProducedSamples: {
        for (final side in stopSides)
          side == WheelSide.left ? 'L' : 'R':
              syncState.bySide[side]!.acqHealth?.producedSamples ?? 0,
      },
      firmwareNotifiedSamples: {
        for (final side in stopSides)
          side == WheelSide.left ? 'L' : 'R':
              syncState.bySide[side]!.acqHealth?.notifiedSamples ?? 0,
      },
      queueDepth: {
        for (final side in stopSides)
          side == WheelSide.left ? 'L' : 'R':
              syncState.bySide[side]!.acqHealth?.queueDepth ?? 0,
      },
    );

    // Save to storage.
    // Save to storage.
    final storage = ref.read(storageRepositoryProvider);
    await storage.saveSession(config.topic, meta, _buffer);

    // Invalidate browse storage to refresh the topic/trial/session list.
    ref.invalidate(topicsProvider);
    ref.invalidate(trialsProvider(config.topic));
    ref.invalidate(sessionsProvider('${config.topic}:${config.trialNumber}'));

    state = state.copyWith(
      status: RecordingStatus.stopped,
      savedSessionId: sessionId,
      lastMeta: meta,
    );
  }

  void _finalizeTimeline(SyncEngineState syncState) {
    final firstBySide = <WheelSide, int>{};
    for (final sample in _buffer) {
      firstBySide.putIfAbsent(sample.wheel, () => sample.reading.tDeviceUs);
    }
    for (var index = 0; index < _buffer.length; index++) {
      final sample = _buffer[index];
      final wheelSync = syncState.bySide[sample.wheel]!;
      final anchor = wheelSync.lastStartFiredUs ?? firstBySide[sample.wheel]!;
      final relativeUs = SessionTimeline.relativeUs(
        timestampUs: sample.reading.tDeviceUs,
        startUs: anchor,
        driftFit: wheelSync.driftFit,
      );
      _buffer[index] = sample.copyWith(timestampSyncedMs: relativeUs / 1000.0);
    }
  }

  String? _degradationReason({
    required List<WheelSide> stopSides,
    required Map<WheelSide, RecoveryMetrics> recoveryMetrics,
    required SyncEngineState syncState,
  }) {
    final reasons = <String>[];
    if (_forcedDegradation case final forced?) reasons.add(forced);
    if (stopSides.any(
      (side) => recoveryMetrics[side]!.unrecoveredSamples > 0,
    )) {
      reasons.add('Unrecovered BLE sequence gaps');
    }
    if (stopSides.any((side) => syncState.bySide[side]!.driftFit == null)) {
      reasons.add('Drift fit unavailable; used START-relative device time');
    }
    for (final side in stopSides) {
      final produced = syncState.bySide[side]!.acqHealth?.producedSamples;
      final saved = _receivedBySide[side] ?? 0;
      if (produced != null && produced > 0 && produced != saved) {
        reasons.add(
          '${_sideLabel(side)} firmware produced $produced but app saved $saved',
        );
      }
    }
    return reasons.isEmpty ? null : reasons.join('; ');
  }

  static int? _startDelta(SyncEngineState syncState) {
    final left = syncState.bySide[WheelSide.left]!;
    final right = syncState.bySide[WheelSide.right]!;
    return SessionTimeline.commonStartDeltaUs(
      leftStartUs: left.lastStartFiredUs,
      rightStartUs: right.lastStartFiredUs,
      leftFit: left.driftFit,
      rightFit: right.driftFit,
    );
  }

  /// Resets to idle state, clearing all session data. The saved session
  /// remains in storage.
  void reset() {
    _buffer.clear();
    _emitTimer?.cancel();
    _emitTimer = null;
    _emitPending = false;
    _firstSampleTimer?.cancel();
    _healthTimer?.cancel();
    _firstSampleSides.clear();
    _expectedSides.clear();
    _healthAtStart.clear();
    _receivedBySide.clear();
    _lastSampleAtMs.clear();
    _forcedDegradation = null;
    _stallAbortStarted = false;
    state = const RecordingState();
  }

  /// A snapshot copy of the in-memory sample buffer. Used by the stopped
  /// view's Preview button to open [SessionPreviewPage] without re-reading
  /// the CSV from disk. Returns a defensive copy so later [reset] / buffer
  /// mutations do not affect the preview page.
  ///
  /// Returns an empty list when no session has been recorded yet or the
  /// buffer has already been cleared by [reset].
  List<BufferedSample> get bufferedSamples => List<BufferedSample>.of(_buffer);
}

/// Minimum interval between `sampleCount` state emissions from
/// [RecordingNotifier].
///
/// Defaults to ~100 ms (10 Hz) in production — the recording UI only needs to
/// show an approximate sample count, not a per-batch update. The buffer always
/// accumulates every sample immediately; only the state emission is throttled
/// to avoid flooding the UI with rebuilds during two-board 100 Hz streaming
/// (which saturates the main isolate and causes app-side BLE packet drops).
/// Tests override this to [Duration.zero] for synchronous assertions.
final recordingEmitIntervalProvider = Provider<Duration>(
  (ref) => const Duration(milliseconds: 250),
  name: 'recordingEmitIntervalProvider',
);

final firstSampleTimeoutProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 2),
  name: 'firstSampleTimeoutProvider',
);

final recordingStopAckTimeoutProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 1),
  name: 'recordingStopAckTimeoutProvider',
);

final recordingProvider = NotifierProvider<RecordingNotifier, RecordingState>(
  RecordingNotifier.new,
);
