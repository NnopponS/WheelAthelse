import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wheelathlete/ble/imu_packet.dart';
import 'package:wheelathlete/records/session_model.dart';
import 'package:wheelathlete/state/ble_providers.dart';
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
    this.error,
  });

  final RecordingStatus status;
  final SessionConfig? config;
  final DateTime? startTime;
  final int sampleCount;
  final String? savedSessionId;
  final String? error;

  RecordingState copyWith({
    RecordingStatus? status,
    SessionConfig? config,
    DateTime? startTime,
    int? sampleCount,
    Object? savedSessionId = _unset,
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

  @override
  RecordingState build() {
    ref.onDispose(() {
      for (final s in _subs.values) {
        s.cancel();
      }
      _subs.clear();
      _trackers.clear();
      _buffer.clear();
    });
    return const RecordingState();
  }

  /// Starts a recording session with the given [config].
  ///
  /// Both wheels must already be connected. Starts IMU streaming on both
  /// sides and subscribes to buffer samples. Throws if already recording.
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
      startTime: startTime,
    );

    _buffer.clear();
    state = RecordingState(
      status: RecordingStatus.recording,
      config: configWithStart,
      startTime: startTime,
    );

    // Start IMU streaming on connected sides only.
    final imuNotifier = ref.read(imuStreamProvider.notifier);
    final connState = ref.read(connectionManagerProvider);
    for (final side in WheelSide.values) {
      final conn = connState.bySide[side]!;
      if (conn.status == ConnectionStatus.connected && conn.deviceId != null) {
        await imuNotifier.start(side);
      }
    }

    // Subscribe to the raw IMU data streams to buffer samples.
    for (final side in WheelSide.values) {
      final conn = connState.bySide[side]!;
      if (conn.status == ConnectionStatus.connected && conn.deviceId != null) {
        await _subscribeImu(side);
      }
    }
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

          final syncState = ref.read(syncEngineProvider);
          final driftFit = syncState.bySide[side]!.driftFit;
          final utcOffsetMs = state.config?.utcOffsetMs;

          for (final sample in result.samples) {
            final reading = sample.toReading(info);
            final relativeSyncedMs = driftFit != null
                ? driftFit.toSyncedMs(sample.tDeviceUs)
                : sample.tDeviceUs / 1000.0;
            final syncedMs = utcOffsetMs != null
                ? relativeSyncedMs + utcOffsetMs
                : relativeSyncedMs;
            _buffer.add(BufferedSample(
              reading: reading,
              wheel: side,
              timestampAppMs: nowMs,
              timestampSyncedMs: syncedMs,
            ));
          }

          if (!ref.mounted) return;
          state = state.copyWith(sampleCount: _buffer.length);
        } on Object catch (e) {
          if (!ref.mounted) return;
          state = state.copyWith(error: 'IMU buffer error: $e');
        }
      },
      onError: (Object e) {
        if (!ref.mounted) return;
        state = state.copyWith(error: 'IMU stream error: $e');
      },
    );
  }

  /// Stops the recording session, saves it to storage, and stops IMU
  /// streaming. Throws if not recording.
  Future<void> stopRecording() async {
    if (state.status != RecordingStatus.recording) {
      throw StateError('Not recording');
    }
    final config = state.config!;
    final startTime = state.startTime!;
    final endTime = DateTime.now();
    final durationMs = endTime.millisecondsSinceEpoch -
        startTime.millisecondsSinceEpoch;

    // Stop IMU streaming on all sides that have active subscriptions.
    final imuNotifier = ref.read(imuStreamProvider.notifier);
    for (final side in _subs.keys) {
      await imuNotifier.stop(side);
    }
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
    final storage = ref.read(storageRepositoryProvider);
    await storage.saveSession(config.topic, meta, _buffer);

    state = state.copyWith(
      status: RecordingStatus.stopped,
      savedSessionId: sessionId,
    );
  }

  /// Resets to idle state, clearing all session data. The saved session
  /// remains in storage.
  void reset() {
    _buffer.clear();
    state = const RecordingState();
  }
}

final recordingProvider =
    NotifierProvider<RecordingNotifier, RecordingState>(
  RecordingNotifier.new,
);
