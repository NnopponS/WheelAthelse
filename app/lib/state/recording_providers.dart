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
    this.markerCount = 0,
    this.markers = const [],
    this.savedSessionId,
    this.error,
  });

  final RecordingStatus status;
  final SessionConfig? config;
  final DateTime? startTime;
  final int sampleCount;
  final int markerCount;
  final List<MarkerEvent> markers;
  final String? savedSessionId;
  final String? error;

  RecordingState copyWith({
    RecordingStatus? status,
    SessionConfig? config,
    DateTime? startTime,
    int? sampleCount,
    int? markerCount,
    List<MarkerEvent>? markers,
    Object? savedSessionId = _unset,
    Object? error = _unset,
  }) =>
      RecordingState(
        status: status ?? this.status,
        config: config ?? this.config,
        startTime: startTime ?? this.startTime,
        sampleCount: sampleCount ?? this.sampleCount,
        markerCount: markerCount ?? this.markerCount,
        markers: markers ?? this.markers,
        savedSessionId: identical(savedSessionId, _unset)
            ? this.savedSessionId
            : savedSessionId as String?,
        error: identical(error, _unset) ? this.error : error as String?,
      );

  static const Object _unset = Object();
}

/// Orchestrates a recording session: start/stop IMU streaming on both wheels,
/// buffer samples with synced timestamps, record Mark Events, and save the
/// session (meta + samples) to the storage repository on stop.
///
/// State machine:
/// - idle → startRecording → recording (streams IMU, buffers samples)
/// - recording → markEvent → recording (records marker, flags next batch)
/// - recording → stopRecording → stopped (saves to storage, stops streams)
/// - stopped → reset → idle (clears state for next session)
class RecordingNotifier extends Notifier<RecordingState> {
  final _buffer = <BufferedSample>[];
  final _subs = <WheelSide, StreamSubscription<List<int>>>{};
  final _trackers = <WheelSide, ImuSeqTracker>{};
  bool _markNextBatch = false;

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

    final startTime = DateTime.now();
    final configWithStart = SessionConfig(
      topic: config.topic,
      trialNumber: config.trialNumber,
      sampleRateHz: config.sampleRateHz,
      athleteName: config.athleteName,
      notes: config.notes,
      utcStartMs: config.utcStartMs,
      startTime: startTime,
    );

    _buffer.clear();
    _markNextBatch = false;
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
          final marker = _markNextBatch;
          _markNextBatch = false;

          final syncState = ref.read(syncEngineProvider);
          final driftFit = syncState.bySide[side]!.driftFit;

          for (final sample in result.samples) {
            final reading = sample.toReading(info);
            final syncedMs = driftFit != null
                ? driftFit.toSyncedMs(sample.tDeviceUs)
                : sample.tDeviceUs / 1000.0;
            _buffer.add(BufferedSample(
              reading: reading,
              wheel: side,
              timestampAppMs: nowMs,
              timestampSyncedMs: syncedMs,
              marker: marker,
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

  /// Drops a sync marker at the current time. The next batch of IMU samples
  /// will have `marker=true` in their [BufferedSample]. Throws if not
  /// recording.
  Future<void> markEvent({String label = ''}) async {
    if (state.status != RecordingStatus.recording) {
      throw StateError('Not recording');
    }
    final now = DateTime.now();
    final offsetMs = now.millisecondsSinceEpoch -
        (state.startTime?.millisecondsSinceEpoch ?? now.millisecondsSinceEpoch);
    final marker = MarkerEvent(
      timestampAppMs: now.millisecondsSinceEpoch,
      offsetFromStartMs: offsetMs,
      label: label,
    );
    _markNextBatch = true;
    state = state.copyWith(
      markerCount: state.markerCount + 1,
      markers: [...state.markers, marker],
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
      markerCount: state.markerCount,
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
    _markNextBatch = false;
    state = const RecordingState();
  }
}

final recordingProvider =
    NotifierProvider<RecordingNotifier, RecordingState>(
  RecordingNotifier.new,
);
