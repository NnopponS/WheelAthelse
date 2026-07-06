import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wheelathlete/ble/imu_packet.dart';
import 'package:wheelathlete/records/session_model.dart';
import 'package:wheelathlete/state/ble_providers.dart';
import 'package:wheelathlete/state/browse_providers.dart';
import 'package:wheelathlete/state/imu_providers.dart';
import 'package:wheelathlete/state/sync_providers.dart';
import 'package:wheelathlete/theme/theme.dart';
import 'package:wheelathlete/widgets/connection_card.dart';

/// Recording state machine status.
enum RecordingStatus { idle, recording, stopped }

/// Whole recording state surfaced to the UI.
class RecordingState {
  const RecordingState({
    this.status = RecordingStatus.idle,
    this.config,
    this.startTime,
    this.sampleCount = 0,
    this.savedSessionId,
    this.lastMeta,
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

  final String? error;

  RecordingState copyWith({
    RecordingStatus? status,
    SessionConfig? config,
    DateTime? startTime,
    int? sampleCount,
    Object? savedSessionId = _unset,
    Object? lastMeta = _unset,
    Object? error = _unset,
  }) =>
      RecordingState(
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
  final _subs = <WheelSide, StreamSubscription<List<int>>>{};
  final _trackers = <WheelSide, ImuSeqTracker>{};

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
    final imuNotifier = ref.read(imuStreamProvider.notifier);
    final connState = ref.read(connectionManagerProvider);
    final futures = <Future<void>>[];
    for (final side in WheelSide.values) {
      if (_subs.containsKey(side)) continue; // already armed
      final conn = connState.bySide[side]!;
      if (conn.status == ConnectionStatus.connected && conn.deviceId != null) {
        futures.add((() async {
          await imuNotifier.start(side);
          await _subscribeImu(side);
        })());
      }
    }
    await Future.wait(futures);
  }

  /// Cancels any pre-armed IMU subscriptions without recording anything.
  /// Used when a countdown is aborted before recording actually begins.
  /// No-op while actively recording.
  Future<void> disarmStreaming() async {
    if (state.status == RecordingStatus.recording) return;
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
  }

  /// Starts a recording session with the given [config].
  ///
  /// Both wheels must already be connected. Arms IMU streaming for any
  /// connected side not already armed by [armStreaming] and subscribes to
  /// buffer samples. Throws if already recording.
  Future<void> startRecording(SessionConfig config) async {
    if (state.status == RecordingStatus.recording) {
      throw StateError('Already recording');
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
    await armStreaming();

    _buffer.clear();
    state = RecordingState(
      status: RecordingStatus.recording,
      config: configWithStart,
      startTime: startTime,
    );

    // Start continuous sync refinement: send SYNC_PINGs to both wheels
    // every 3 seconds during recording. This keeps the drift fit accurate
    // over long sessions by correcting for crystal drift between the phone
    // and M5StickC clocks. The sync engine's MinRttTracker keeps the best
    // (lowest-RTT) offset, and the DriftFit is recalculated from all
    // collected points, so extra pings only improve accuracy.
    _startContinuousSync();
  }

  /// Interval between continuous sync pings during recording.
  static const _continuousSyncInterval = Duration(seconds: 3);

  void _startContinuousSync() {
    _continuousSyncTimer?.cancel();
    _continuousSyncTimer = Timer.periodic(_continuousSyncInterval, (_) {
      if (!ref.mounted || state.status != RecordingStatus.recording) {
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
      Future.wait(futures); // fire-and-forget — errors handled by sync engine
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

    final ble = ref.read(bleRepositoryProvider);
    _trackers[side] = ImuSeqTracker();

    _subs[side] = ble.imuData(deviceId).listen(
      (bytes) {
        try {
          final tracker = _trackers[side]!;
          final result = ImuPacketParser.parseBatchWithGaps(bytes, tracker);
          final nowMs = DateTime.now().millisecondsSinceEpoch;

          final baseUtcMs = state.config?.utcStartMs ?? state.config?.startTime?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch;
          final alignedBaseUtcMs = (baseUtcMs ~/ 1000) * 1000;
          final sampleRate = state.config?.sampleRateHz ?? 100;

          for (final sample in result.samples) {
            final reading = sample.toReading(info);
            final syncedMs = alignedBaseUtcMs + (sample.seq * 1000.0 / sampleRate);
            _buffer.add(BufferedSample(
              reading: reading,
              wheel: side,
              timestampAppMs: nowMs,
              timestampSyncedMs: syncedMs,
            ));
          }

          if (!ref.mounted) return;
          _emitSampleCount();
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

  /// Stops the recording session, saves it to storage, and stops IMU
  /// streaming. Throws if not recording.
  Future<void> stopRecording() async {
    if (state.status != RecordingStatus.recording) {
      throw StateError('Not recording');
    }
    // Flush any pending throttled sampleCount so the final state is consistent
    // before we read _buffer.length for the session meta.
    _flushEmit();
    final config = state.config!;
    final startTime = state.startTime!;
    final endTime = DateTime.now();
    final durationMs = endTime.millisecondsSinceEpoch -
        startTime.millisecondsSinceEpoch;

    // Stop continuous sync refinement.
    _stopContinuousSync();

    // Stop IMU streaming on all sides in parallel.
    final imuNotifier = ref.read(imuStreamProvider.notifier);
    await Future.wait(
      _subs.keys.map((side) => imuNotifier.stop(side)),
    );
    for (final s in _subs.values) {
      await s.cancel();
    }
    _subs.clear();

    // Build session meta with sync quality from the sync engine.
    final syncState = ref.read(syncEngineProvider);
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

  /// Resets to idle state, clearing all session data. The saved session
  /// remains in storage.
  void reset() {
    _buffer.clear();
    _emitTimer?.cancel();
    _emitTimer = null;
    _emitPending = false;
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
  (ref) => const Duration(milliseconds: 100),
  name: 'recordingEmitIntervalProvider',
);

final recordingProvider =
    NotifierProvider<RecordingNotifier, RecordingState>(
  RecordingNotifier.new,
);
