import 'package:wheelathlete/ble/imu_packet.dart';
import 'package:wheelathlete/theme/theme.dart';

/// A sync marker dropped by the user during recording (Mark Event button).
///
/// Used to align IMU data with the camera video. The timestamp is the phone
/// epoch ms when the button was pressed; `offsetFromStartMs` is relative to
/// the session start for quick reference.
class MarkerEvent {
  const MarkerEvent({
    required this.timestampAppMs,
    required this.offsetFromStartMs,
    this.label = '',
  });

  /// Phone epoch milliseconds when the marker was dropped.
  final int timestampAppMs;

  /// Milliseconds from session start (for display + CSV marker column).
  final int offsetFromStartMs;

  /// Optional label (e.g. "push-off", "brake"). Empty by default.
  final String label;
}

/// Configuration for a recording session — chosen before pressing Start.
class SessionConfig {
  const SessionConfig({
    required this.topic,
    required this.trialNumber,
    required this.sampleRateHz,
    this.athleteName,
    this.notes,
    this.utcStartMs,
    this.utcOffsetMs,
    this.protocolTemplateId,
    DateTime? startTime,
  }) : _startTime = startTime;

  /// Topic/subject folder name (e.g. "sprint_test", "athlete_A").
  final String topic;

  /// Trial number within this topic (auto-incremented, user can override).
  final int trialNumber;

  /// Sampling rate in Hz (50/100/200, sent to firmware via SET_RATE).
  final int sampleRateHz;

  /// Optional athlete/test subject name.
  final String? athleteName;

  /// Optional notes for this session.
  final String? notes;

  /// UTC epoch milliseconds of the scheduled start instant (for camera
  /// alignment). Computed by the countdown flow as
  /// `utc_epoch_now + (T_start - now_phone)`. Null when the session was
  /// started without a countdown (legacy/immediate start).
  final int? utcStartMs;

  /// Legacy v3 field retained only for backward session compatibility. New
  /// recordings never add this value to sample timestamps; UTC belongs in
  /// metadata while samples stay START-relative.
  final int? utcOffsetMs;

  /// Optional id of the protocol template this session was recorded under
  /// (Phase 3, §6). When set, the Experiment tracker dashboard groups this
  /// session under that template. Null for "Custom" (manual topic) sessions.
  final String? protocolTemplateId;
  final DateTime? _startTime;

  /// Start time of the session, or null if not set.
  DateTime? get startTime => _startTime;

  /// Zero-padded trial folder name (trial_01, trial_02, ..., trial_10).
  String get trialFolderName =>
      'trial_${trialNumber.toString().padLeft(2, '0')}';

  /// Session ID — hex timestamp, unique enough for file naming.
  String get sessionId {
    final t = _startTime ?? DateTime.now();
    return t.millisecondsSinceEpoch.toRadixString(16);
  }
}

/// Metadata written to `session_<id>_meta.json` after recording stops.
///
/// Captures everything needed to reproduce/interpret the session: who, when,
/// how long, sample rate, sync quality (offset + drift residual), markers,
/// and optional video file name for alignment.
class SessionMeta {
  const SessionMeta({
    required this.sessionId,
    required this.topic,
    required this.trialNumber,
    required this.sampleRateHz,
    required this.startTime,
    required this.durationMs,
    required this.sampleCount,
    required this.markerCount,
    this.athleteName,
    this.offsetUsLeft,
    this.offsetUsRight,
    this.driftResidualRmsMsLeft,
    this.driftResidualRmsMsRight,
    this.notes,
    this.videoFileName,
    this.utcStartMs,
    this.tags = const [],
    this.protocolTemplateId,
    this.recordedSides = const [],
    this.boardModels = const {},
    this.firmwareVersions = const {},
    this.sequenceGaps = const {},
    this.dropCounts = const {},
    this.sampleQueueDrops = const {},
    this.imuFifoFaults = const {},
    this.imuFifoDroppedSamples = const {},
    this.startAcknowledgedUs = const {},
    this.startDeltaUs,
    this.recoveredSamples = const {},
    this.unrecoveredSamples = const {},
    this.replayAttempts = const {},
    this.transportFailures = const {},
    this.firmwareProducedSamples = const {},
    this.firmwareNotifiedSamples = const {},
    this.queueDepth = const {},
    this.degradationReason,
    this.schemaVersion = 4,
    this.protocolVersion = '1.8.0',
  });

  final String sessionId;
  final String topic;
  final int trialNumber;
  final String? athleteName;
  final int sampleRateHz;
  final DateTime startTime;
  final int durationMs;
  final int sampleCount;
  final int markerCount;
  final int? offsetUsLeft;
  final int? offsetUsRight;
  final double? driftResidualRmsMsLeft;
  final double? driftResidualRmsMsRight;
  final String? notes;
  final String? videoFileName;

  /// UTC epoch milliseconds of the scheduled start instant (for camera
  /// alignment). Null when the session was started without a countdown.
  final int? utcStartMs;

  /// Free-form tags/labels for this session (e.g. "good", "bad-take",
  /// "athlete-A"). Used for filtering in Browse + the Experiment tracker.
  /// Defaults to an empty list. Old sessions without `tags` default to `[]`.
  final List<String> tags;

  /// Optional id of the protocol template this session was recorded under
  /// (Phase 3, §6). Links the session to a [ProtocolTemplate] for the
  /// Experiment tracker dashboard. Null for "Custom" (manual topic) sessions
  /// and old sessions.
  final String? protocolTemplateId;
  final List<String> recordedSides;
  final Map<String, String> boardModels;
  final Map<String, String> firmwareVersions;
  final Map<String, int> sequenceGaps;
  final Map<String, int> dropCounts;
  final Map<String, int> sampleQueueDrops;
  final Map<String, int> imuFifoFaults;
  final Map<String, int> imuFifoDroppedSamples;
  final Map<String, int> startAcknowledgedUs;
  final int? startDeltaUs;
  final Map<String, int> recoveredSamples;
  final Map<String, int> unrecoveredSamples;
  final Map<String, int> replayAttempts;
  final Map<String, int> transportFailures;
  final Map<String, int> firmwareProducedSamples;
  final Map<String, int> firmwareNotifiedSamples;
  final Map<String, int> queueDepth;
  final String? degradationReason;
  final int schemaVersion;
  final String protocolVersion;

  Map<String, dynamic> toJson() => {
    'session_id': sessionId,
    'topic': topic,
    'trial_number': trialNumber,
    'athlete_name': athleteName,
    'sample_rate_hz': sampleRateHz,
    'start_time': startTime.toUtc().toIso8601String(),
    'duration_ms': durationMs,
    'sample_count': sampleCount,
    'marker_count': markerCount,
    'offset_us_left': offsetUsLeft,
    'offset_us_right': offsetUsRight,
    'drift_residual_rms_ms_left': driftResidualRmsMsLeft,
    'drift_residual_rms_ms_right': driftResidualRmsMsRight,
    'notes': notes,
    'video_file_name': videoFileName,
    'utc_start_ms': utcStartMs,
    'tags': tags,
    'protocol_template_id': protocolTemplateId,
    'recorded_sides': recordedSides,
    'board_models': boardModels,
    'firmware_versions': firmwareVersions,
    'sequence_gaps': sequenceGaps,
    'drop_counts': dropCounts,
    'sample_queue_drops': sampleQueueDrops,
    'imu_fifo_faults': imuFifoFaults,
    'imu_fifo_dropped_samples': imuFifoDroppedSamples,
    'start_acknowledged_us': startAcknowledgedUs,
    'start_delta_us': startDeltaUs,
    'recovered_samples': recoveredSamples,
    'unrecovered_samples': unrecoveredSamples,
    'replay_attempts': replayAttempts,
    'transport_failures': transportFailures,
    'firmware_produced_samples': firmwareProducedSamples,
    'firmware_notified_samples': firmwareNotifiedSamples,
    'queue_depth': queueDepth,
    'degradation_reason': degradationReason,
    'schema_version': schemaVersion,
    'protocol_version': protocolVersion,
  };

  factory SessionMeta.fromJson(Map<String, dynamic> json) => SessionMeta(
    sessionId: json['session_id'] as String,
    topic: json['topic'] as String,
    trialNumber: json['trial_number'] as int,
    athleteName: json['athlete_name'] as String?,
    sampleRateHz: json['sample_rate_hz'] as int,
    startTime: DateTime.parse(json['start_time'] as String),
    durationMs: json['duration_ms'] as int,
    sampleCount: json['sample_count'] as int,
    markerCount: json['marker_count'] as int,
    offsetUsLeft: json['offset_us_left'] as int?,
    offsetUsRight: json['offset_us_right'] as int?,
    driftResidualRmsMsLeft: (json['drift_residual_rms_ms_left'] as num?)
        ?.toDouble(),
    driftResidualRmsMsRight: (json['drift_residual_rms_ms_right'] as num?)
        ?.toDouble(),
    notes: json['notes'] as String?,
    videoFileName: json['video_file_name'] as String?,
    utcStartMs: json['utc_start_ms'] as int?,
    tags:
        (json['tags'] as List?)
            ?.map((e) => e as String)
            .toList(growable: false) ??
        const [],
    protocolTemplateId: json['protocol_template_id'] as String?,
    recordedSides:
        (json['recorded_sides'] as List?)?.cast<String>() ?? const [],
    boardModels:
        (json['board_models'] as Map?)?.cast<String, String>() ?? const {},
    firmwareVersions:
        (json['firmware_versions'] as Map?)?.cast<String, String>() ?? const {},
    sequenceGaps:
        (json['sequence_gaps'] as Map?)?.map(
          (key, value) => MapEntry(key as String, value as int),
        ) ??
        const {},
    dropCounts:
        (json['drop_counts'] as Map?)?.map(
          (key, value) => MapEntry(key as String, value as int),
        ) ??
        const {},
    sampleQueueDrops: _intMap(json['sample_queue_drops']),
    imuFifoFaults: _intMap(json['imu_fifo_faults']),
    imuFifoDroppedSamples: _intMap(json['imu_fifo_dropped_samples']),
    startAcknowledgedUs:
        (json['start_acknowledged_us'] as Map?)?.map(
          (key, value) => MapEntry(key as String, value as int),
        ) ??
        const {},
    startDeltaUs: json['start_delta_us'] as int?,
    recoveredSamples: _intMap(json['recovered_samples']),
    unrecoveredSamples: _intMap(json['unrecovered_samples']),
    replayAttempts: _intMap(json['replay_attempts']),
    transportFailures: _intMap(json['transport_failures']),
    firmwareProducedSamples: _intMap(json['firmware_produced_samples']),
    firmwareNotifiedSamples: _intMap(json['firmware_notified_samples']),
    queueDepth: _intMap(json['queue_depth']),
    degradationReason: json['degradation_reason'] as String?,
    schemaVersion: json['schema_version'] as int? ?? 1,
    protocolVersion: json['protocol_version'] as String? ?? '1.1.0',
  );

  static Map<String, int> _intMap(Object? value) =>
      (value as Map?)?.map(
        (key, item) => MapEntry(key as String, (item as num).toInt()),
      ) ??
      const {};
}

/// One IMU sample buffered during recording, enriched with wheel side +
/// timestamps for CSV export.
///
/// The CSV row (§3 of architecture.md) is:
/// `seq, wheel, timestamp_app_ms, timestamp_device_us, timestamp_synced_ms,
/// ax, ay, az, gx, gy, gz, marker`
class BufferedSample {
  const BufferedSample({
    required this.reading,
    required this.wheel,
    required this.timestampAppMs,
    required this.timestampSyncedMs,
    this.marker = false,
  });

  final ImuReading reading;
  final WheelSide wheel;

  /// Phone epoch ms when the batch was received (has BLE jitter).
  final int timestampAppMs;

  /// Synced timeline milliseconds from the synchronized START. Absolute UTC
  /// is stored only in [SessionMeta.utcStartMs].
  final double timestampSyncedMs;

  /// True if a Mark Event was active when this sample was buffered.
  final bool marker;

  BufferedSample copyWith({double? timestampSyncedMs}) => BufferedSample(
    reading: reading,
    wheel: wheel,
    timestampAppMs: timestampAppMs,
    timestampSyncedMs: timestampSyncedMs ?? this.timestampSyncedMs,
    marker: marker,
  );
}
