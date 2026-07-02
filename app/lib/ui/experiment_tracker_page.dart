import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wheelathlete/state/experiment_tracker_providers.dart';
import 'package:wheelathlete/state/protocol_providers.dart';
import 'package:wheelathlete/theme/theme.dart';
import 'package:wheelathlete/widgets/protocol_template_card.dart';

/// Experiment tracker dashboard (Phase 3, §8) — the 4th tab.
///
/// Lists every protocol template as a [ProtocolTemplateCard] with a progress
/// bar (`sessions / targetTrialCount`). Tapping a card switches to the Browse
/// tab at that template's topic via [onOpenTopic]. The "New Template" FAB opens
/// a create-template dialog (name, description, topicName, targetTrialCount,
/// sampleRateHz) that persists via [protocolTemplateNotifierProvider].
class ExperimentTrackerPage extends ConsumerWidget {
  const ExperimentTrackerPage({super.key, required this.onOpenTopic});

  /// Called with a template's topicName when its card is tapped. The home shell
  /// wires this to switch to the Browse tab and pre-select that topic.
  final ValueChanged<String> onOpenTopic;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncProgress = ref.watch(experimentProgressProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateTemplateDialog(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Template'),
      ),
      body: asyncProgress.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Text('Failed to load experiments: $e'),
          ),
        ),
        data: (progressList) {
          if (progressList.isEmpty) {
            return const _EmptyState();
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              96, // leave room for the FAB
            ),
            itemCount: progressList.length,
            separatorBuilder: (context, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, i) {
              final p = progressList[i];
              return ProtocolTemplateCard(
                progress: p,
                onTap: () => onOpenTopic(p.template.topicName),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _showCreateTemplateDialog(BuildContext context, WidgetRef ref) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => const _CreateTemplateDialog(),
    );
  }
}

/// Empty state shown when no protocol templates exist yet.
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.science_outlined,
              size: 64,
              color: theme.disabledColor,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'No experiments yet',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Create a protocol template to start tracking experiments',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

/// Dialog for creating a new protocol template. Fields: name (required),
/// description (optional), topicName (required), targetTrialCount (required,
/// dropdown 1–20), sampleRateHz (optional, dropdown 50/100/200, default 100).
///
/// On save, calls [ProtocolTemplateNotifier.createTemplate] and refreshes the
/// dashboard via [experimentProgressProvider] invalidation (the notifier's
/// `refresh` already invalidates [protocolTemplatesProvider]; we also invalidate
/// the progress provider so the new template appears immediately).
class _CreateTemplateDialog extends ConsumerStatefulWidget {
  const _CreateTemplateDialog();

  @override
  ConsumerState<_CreateTemplateDialog> createState() =>
      _CreateTemplateDialogState();
}

class _CreateTemplateDialogState extends ConsumerState<_CreateTemplateDialog> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _topicController = TextEditingController();
  int _targetTrialCount = 5;
  int _sampleRateHz = 100;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _topicController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final topic = _topicController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Name is required');
      return;
    }
    if (topic.isEmpty) {
      setState(() => _error = 'Topic name is required');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final notifier = ref.read(protocolTemplateNotifierProvider.notifier);
      await notifier.createTemplate(
        name: name,
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        topicName: topic,
        targetTrialCount: _targetTrialCount,
        sampleRateHz: _sampleRateHz,
      );
      // Refresh the dashboard progress so the new template shows immediately.
      ref.invalidate(experimentProgressProvider);
      if (mounted) Navigator.of(context).pop();
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('New Protocol Template'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Name *',
                hintText: 'e.g. 20m Sprint Test',
              ),
              autofocus: true,
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description',
                hintText: 'Optional',
              ),
              maxLines: 2,
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _topicController,
              decoration: const InputDecoration(
                labelText: 'Topic name *',
                hintText: 'e.g. sprint_20m',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _targetTrialCount,
                    decoration: const InputDecoration(
                      labelText: 'Target trials',
                    ),
                    items: [
                      for (var n = 1; n <= 20; n++)
                        DropdownMenuItem(value: n, child: Text('$n')),
                    ],
                    onChanged: (v) =>
                        setState(() => _targetTrialCount = v ?? 5),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _sampleRateHz,
                    decoration: const InputDecoration(
                      labelText: 'Sample rate (Hz)',
                    ),
                    items: const [
                      DropdownMenuItem(value: 50, child: Text('50')),
                      DropdownMenuItem(value: 100, child: Text('100')),
                      DropdownMenuItem(value: 200, child: Text('200')),
                    ],
                    onChanged: (v) =>
                        setState(() => _sampleRateHz = v ?? 100),
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create'),
        ),
      ],
    );
  }
}
