import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wheelathlete/export/export_actions.dart';
import 'package:wheelathlete/export/export_providers.dart';
import 'package:wheelathlete/records/quality_badge.dart';
import 'package:wheelathlete/records/session_model.dart';
import 'package:wheelathlete/state/ble_providers.dart';
import 'package:wheelathlete/state/browse_providers.dart';
import 'package:wheelathlete/state/home_providers.dart';
import 'package:wheelathlete/state/model_management_providers.dart';
import 'package:wheelathlete/state/preview_providers.dart';
import 'package:wheelathlete/theme/theme.dart';
import 'package:wheelathlete/ui/session_preview_page.dart';
import 'package:wheelathlete/widgets/status_badge.dart';
import 'package:wheelathlete/widgets/widgets.dart';

/// State for the selected sessions in the Results page.
class ResultsSelectedSessionIdsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => {};

  void set(Set<String> val) => state = val;

  void clear() => state = {};
}

final resultsSelectedSessionIdsProvider =
    NotifierProvider<ResultsSelectedSessionIdsNotifier, Set<String>>(
  ResultsSelectedSessionIdsNotifier.new,
);

/// State for the active topic filter in the Results page.
class ResultsTopicFilterNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? val) => state = val;
}

final resultsTopicFilterProvider =
    NotifierProvider<ResultsTopicFilterNotifier, String?>(
  ResultsTopicFilterNotifier.new,
);

/// State for search text query in the Results page.
class ResultsSearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String val) => state = val;
}

final resultsSearchQueryProvider =
    NotifierProvider<ResultsSearchQueryNotifier, String>(
  ResultsSearchQueryNotifier.new,
);

/// Dedicated Results screen:
/// - Session folder header with Refresh and Export All ZIP
/// - Search and filter bar (Topic, search query)
/// - Multi-session batch selection (Select all / Clear)
/// - Batch export actions (CSV, ZIP)
/// - "Open in Model" action (routes session into Model trajectory inference)
/// - Session list with rich telemetry summary, sync quality badge, and playback preview
class ResultsPage extends ConsumerWidget {
  const ResultsPage({super.key});

  Future<void> _exportSelectedCsv(BuildContext context, WidgetRef ref, List<SessionMeta> selected) async {
    if (selected.isEmpty) return;
    final export = ref.read(exportActionsProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      for (final s in selected) {
        await export.share(
          level: ExportLevel.session,
          topic: s.topic,
          trialNumber: s.trialNumber,
          sessionId: s.sessionId,
        );
      }
      messenger.showSnackBar(
        SnackBar(content: Text('Exported ${selected.length} session(s).')),
      );
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  Future<void> _deleteSelected(BuildContext context, WidgetRef ref, List<SessionMeta> selected) async {
    if (selected.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${selected.length} recording(s)?'),
        content: const Text('This will permanently delete the selected recording data. This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final storage = ref.read(storageRepositoryProvider);
    for (final s in selected) {
      await storage.deleteSession(s.topic, s.trialNumber, s.sessionId);
    }
    ref.read(resultsSelectedSessionIdsProvider.notifier).clear();
    ref.invalidate(allSessionsProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted ${selected.length} recording(s).')),
      );
    }
  }

  void _openInModel(WidgetRef ref, String sessionId) {
    ref.read(selectedModelSessionIdProvider.notifier).set(sessionId);
    ref.read(homeTabIndexProvider.notifier).setTab(HomeTabNotifier.model);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sessionsAsync = ref.watch(allSessionsProvider);
    final selectedIds = ref.watch(resultsSelectedSessionIdsProvider);
    final topicFilter = ref.watch(resultsTopicFilterProvider);
    final query = ref.watch(resultsSearchQueryProvider).toLowerCase().trim();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Results'),
        actions: [
          IconButton(
            tooltip: 'Export all data (ZIP)',
            icon: const Icon(Icons.folder_zip_rounded),
            onPressed: () async {
              try {
                final export = ref.read(exportActionsProvider);
                final path = await export.exportAllZip(
                  pickDirectory: pickDirectory,
                  writeFile: writeCsvFile,
                );
                if (path != null && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Exported ZIP to $path')),
                  );
                }
              } on Object catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Export failed: $e')),
                  );
                }
              }
            },
          ),
          IconButton(
            tooltip: 'Refresh sessions',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(allSessionsProvider),
          ),
        ],
      ),
      body: sessionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error loading recordings: $err')),
        data: (allSessions) {
          // Gather distinct topics
          final topics = allSessions.map((s) => s.topic).toSet().toList()..sort();

          // Filter by topic and search query
          final filtered = allSessions.where((s) {
            if (topicFilter != null && s.topic != topicFilter) return false;
            if (query.isNotEmpty) {
              final match = s.sessionId.toLowerCase().contains(query) ||
                  s.topic.toLowerCase().contains(query) ||
                  (s.notes?.toLowerCase().contains(query) ?? false);
              if (!match) return false;
            }
            return true;
          }).toList();

          final selectedSessions = allSessions.where((s) => selectedIds.contains(s.sessionId)).toList();

          return Column(
            children: [
              // Search and Filter Bar
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Search recordings…',
                          prefixIcon: const Icon(Icons.search_rounded),
                          contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                          border: const OutlineInputBorder(),
                          suffixIcon: query.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded),
                                  onPressed: () => ref.read(resultsSearchQueryProvider.notifier).set(''),
                                )
                              : null,
                        ),
                        onChanged: (val) => ref.read(resultsSearchQueryProvider.notifier).set(val),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      flex: 1,
                      child: DropdownButtonFormField<String?>(
                        initialValue: topicFilter,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xs),
                        ),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('All topics')),
                          for (final t in topics)
                            DropdownMenuItem(value: t, child: Text(t, overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: (val) => ref.read(resultsTopicFilterProvider.notifier).set(val),
                      ),
                    ),
                  ],
                ),
              ),

              // Batch Selection Actions Card
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              selectedIds.isEmpty
                                  ? '${filtered.length} recordings'
                                  : '${selectedIds.length} of ${filtered.length} selected',
                              style: theme.textTheme.titleSmall,
                            ),
                            const Spacer(),
                            TextButton(
                              onPressed: () {
                                if (selectedIds.length == filtered.length) {
                                  ref.read(resultsSelectedSessionIdsProvider.notifier).clear();
                                } else {
                                  ref.read(resultsSelectedSessionIdsProvider.notifier).set(
                                      filtered.map((s) => s.sessionId).toSet());
                                }
                              },
                              child: Text(selectedIds.length == filtered.length ? 'Deselect all' : 'Select all'),
                            ),
                          ],
                        ),
                        if (selectedIds.isNotEmpty) ...[
                          const Divider(),
                          Wrap(
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.xs,
                            children: [
                              FilledButton.tonalIcon(
                                icon: const Icon(Icons.psychology_rounded),
                                label: const Text('Open in Model'),
                                onPressed: selectedSessions.isNotEmpty
                                    ? () => _openInModel(ref, selectedSessions.first.sessionId)
                                    : null,
                              ),
                              FilledButton.icon(
                                icon: const Icon(Icons.share_rounded),
                                label: const Text('Export CSV(s)'),
                                onPressed: () => _exportSelectedCsv(context, ref, selectedSessions),
                              ),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.delete_outline_rounded),
                                style: OutlinedButton.styleFrom(foregroundColor: scheme.error),
                                label: const Text('Delete'),
                                onPressed: () => _deleteSelected(context, ref, selectedSessions),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),

              // Session List
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text(
                          allSessions.isEmpty ? 'No recorded sessions yet.' : 'No sessions matching filter.',
                          style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (context, index) {
                          final session = filtered[index];
                          final isSelected = selectedIds.contains(session.sessionId);
                          final syncLevel = QualityBadge.fromMeta(session);

                          return Card(
                            elevation: isSelected ? 3 : 1,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppRadius.md),
                              side: BorderSide(
                                color: isSelected ? scheme.primary : Colors.transparent,
                                width: 1.5,
                              ),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(AppRadius.md),
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => SessionPreviewPage(
                                      source: DiskPreviewSource(
                                        topic: session.topic,
                                        trialNumber: session.trialNumber,
                                        sessionId: session.sessionId,
                                      ),
                                      title: '${session.topic} · Trial ${session.trialNumber}',
                                    ),
                                  ),
                                );
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(AppSpacing.md),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Checkbox(
                                          value: isSelected,
                                          onChanged: (val) {
                                            final current = Set<String>.from(ref.read(resultsSelectedSessionIdsProvider));
                                            if (val == true) {
                                              current.add(session.sessionId);
                                            } else {
                                              current.remove(session.sessionId);
                                            }
                                            ref.read(resultsSelectedSessionIdsProvider.notifier).set(current);
                                          },
                                        ),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '${session.topic} · Trial ${session.trialNumber}',
                                                style: theme.textTheme.titleMedium?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              Text(
                                                session.sessionId,
                                                style: theme.textTheme.bodySmall?.copyWith(
                                                  color: scheme.onSurfaceVariant,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        StatusBadge(
                                          label: syncLevel.name,
                                          tone: switch (syncLevel) {
                                            SyncQuality.good => BadgeTone.success,
                                            SyncQuality.fair => BadgeTone.warning,
                                            SyncQuality.poor => BadgeTone.danger,
                                            SyncQuality.unknown => BadgeTone.neutral,
                                          },
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: AppSpacing.xs),
                                    Wrap(
                                      spacing: AppSpacing.md,
                                      children: [
                                        Text('${(session.durationMs / 1000).toStringAsFixed(1)} s'),
                                        Text('${session.sampleCount} samples'),
                                        Text('${session.sampleRateHz} Hz'),
                                        Text('Sides: ${session.recordedSides.join(', ')}'),
                                      ],
                                    ),
                                    const SizedBox(height: AppSpacing.sm),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        TextButton.icon(
                                          icon: const Icon(Icons.psychology_rounded, size: 18),
                                          label: const Text('Open in Model'),
                                          onPressed: () => _openInModel(ref, session.sessionId),
                                        ),
                                        const SizedBox(width: AppSpacing.xs),
                                        FilledButton.tonalIcon(
                                          icon: const Icon(Icons.play_circle_outline_rounded, size: 18),
                                          label: const Text('Preview'),
                                          onPressed: () {
                                            Navigator.of(context).push(
                                              MaterialPageRoute<void>(
                                                builder: (_) => SessionPreviewPage(
                                                  source: DiskPreviewSource(
                                                    topic: session.topic,
                                                    trialNumber: session.trialNumber,
                                                    sessionId: session.sessionId,
                                                  ),
                                                  title: '${session.topic} · Trial ${session.trialNumber}',
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
