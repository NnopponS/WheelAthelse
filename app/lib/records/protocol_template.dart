/// A reusable experiment definition (Phase 3, §1 of architecture-phase3.md).
///
/// A protocol template captures the metadata the user re-types every session
/// for a given experiment (e.g. "20m Sprint Test"): a name, description, the
/// topic folder it maps to, the target number of trials, and the default
/// sample rate. The Experiment tracker dashboard groups sessions by template
/// and shows progress against [targetTrialCount] (e.g. "3/5 done").
///
/// Templates are persisted as a single `protocols.json` file in the app
/// documents directory (alongside `WheelAthleteData/`) by
/// [ProtocolRepository].
class ProtocolTemplate {
  const ProtocolTemplate({
    required this.id,
    required this.name,
    required this.topicName,
    required this.targetTrialCount,
    required this.createdAt,
    this.description,
    this.sampleRateHz = 100,
  });

  /// Hex timestamp — same pattern as `SessionConfig.sessionId`
  /// (`DateTime.now().millisecondsSinceEpoch.toRadixString(16)`).
  final String id;

  /// Human-readable name, e.g. "20m Sprint Test".
  final String name;

  /// Optional longer description, e.g. "From standing start, 20m max effort".
  final String? description;

  /// Topic folder name this template is linked to. The folder is
  /// auto-created when a session is recorded under this template.
  final String topicName;

  /// Target number of trials for this protocol. The dashboard shows
  /// progress as `sessions / targetTrialCount` (e.g. "3/5 done").
  final int targetTrialCount;

  /// Default sampling rate in Hz (50/100/200). Defaults to 100.
  final int sampleRateHz;

  /// When the template was created.
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'topic_name': topicName,
        'target_trial_count': targetTrialCount,
        'sample_rate_hz': sampleRateHz,
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  factory ProtocolTemplate.fromJson(Map<String, dynamic> json) {
    final sampleRate = json['sample_rate_hz'];
    return ProtocolTemplate(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      topicName: json['topic_name'] as String,
      targetTrialCount: json['target_trial_count'] as int,
      sampleRateHz: sampleRate == null ? 100 : (sampleRate as num).toInt(),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  ProtocolTemplate copyWith({
    String? name,
    String? description,
    String? topicName,
    int? targetTrialCount,
    int? sampleRateHz,
  }) =>
      ProtocolTemplate(
        id: id,
        name: name ?? this.name,
        description: description ?? this.description,
        topicName: topicName ?? this.topicName,
        targetTrialCount: targetTrialCount ?? this.targetTrialCount,
        sampleRateHz: sampleRateHz ?? this.sampleRateHz,
        createdAt: createdAt,
      );
}
