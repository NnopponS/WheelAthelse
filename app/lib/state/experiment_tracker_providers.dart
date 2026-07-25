import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wheelathlete/records/protocol_template.dart';
import 'package:wheelathlete/records/session_model.dart';
import 'package:wheelathlete/state/ble_providers.dart';
import 'package:wheelathlete/state/protocol_providers.dart';

/// Progress of one protocol template against its target trial count (Phase 3,
/// §8 Experiment tracker dashboard).
///
/// The dashboard groups all sessions (across every topic/trial) by template and
/// shows `sessionCount / targetTrialCount` as a progress bar. Sessions are
/// matched to a template by `protocolTemplateId` first; sessions recorded
/// before templates existed (or under a "Custom" topic) fall back to matching
/// by `topicName`.
class ExperimentProgress {
  const ExperimentProgress({
    required this.template,
    required this.sessionCount,
    this.lastSessionDate,
  });

  final ProtocolTemplate template;
  final int sessionCount;
  final DateTime? lastSessionDate;

  /// Fraction of the target trial count completed, clamped to [0.0, 1.0] so the
  /// [LinearProgressIndicator] never overflows when extra sessions exist.
  double get progress => template.targetTrialCount > 0
      ? (sessionCount / template.targetTrialCount).clamp(0.0, 1.0)
      : 0.0;

  /// True when the target trial count has been met or exceeded.
  bool get isComplete =>
      template.targetTrialCount > 0 &&
      sessionCount >= template.targetTrialCount;
}

/// Loads all protocol templates and counts the sessions grouped under each one
/// (Phase 3, §8). Sessions are matched by `protocolTemplateId`; sessions with a
/// null template id fall back to matching by `topicName`. The returned list is
/// sorted by template name (the same order [ProtocolRepository.listTemplates]
/// returns).
final experimentProgressProvider = FutureProvider<List<ExperimentProgress>>((
  ref,
) async {
  final templates = await ref.read(protocolRepositoryProvider).listTemplates();
  final sessions = await ref.read(storageRepositoryProvider).listAllSessions();
  return computeExperimentProgress(templates, sessions);
});

/// Maps topic names to their [ExperimentProgress] (if a protocol template
/// exists for that topic). Used by the Browse page's topic list to show
/// progress bars inline. Topics without a template are absent from the map.
final topicProgressProvider = FutureProvider<Map<String, ExperimentProgress>>((
  ref,
) async {
  final progressList = await ref.watch(experimentProgressProvider.future);
  return {for (final p in progressList) p.template.topicName: p};
});

/// Pure function that groups [sessions] under [templates] and returns one
/// [ExperimentProgress] per template, sorted by template name. Extracted from
/// the provider so it can be unit-tested directly without a ProviderContainer.
List<ExperimentProgress> computeExperimentProgress(
  List<ProtocolTemplate> templates,
  List<SessionMeta> sessions,
) {
  // Index templates by id and by topicName for O(n) grouping.
  final byId = <String, ProtocolTemplate>{for (final t in templates) t.id: t};
  // Track counts + last session date per template id.
  final counts = <String, int>{};
  final lastDates = <String, DateTime>{};

  for (final session in sessions) {
    String? templateId = session.protocolTemplateId;
    // Fallback: match by topicName when the session has no template id.
    if (templateId == null) {
      for (final t in templates) {
        if (t.topicName == session.topic) {
          templateId = t.id;
          break;
        }
      }
    }
    if (templateId == null) continue; // session belongs to no template
    // Only count sessions whose template still exists.
    if (!byId.containsKey(templateId)) continue;
    counts[templateId] = (counts[templateId] ?? 0) + 1;
    final existing = lastDates[templateId];
    if (existing == null || session.startTime.isAfter(existing)) {
      lastDates[templateId] = session.startTime;
    }
  }

  // templates is already sorted by name (listTemplates sorts), but be safe.
  final sorted = List<ProtocolTemplate>.from(templates)
    ..sort((a, b) => a.name.compareTo(b.name));
  return sorted
      .map(
        (t) => ExperimentProgress(
          template: t,
          sessionCount: counts[t.id] ?? 0,
          lastSessionDate: lastDates[t.id],
        ),
      )
      .toList(growable: false);
}
