import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wheelathlete/records/session_model.dart';
import 'package:wheelathlete/records/storage_repository.dart';
import 'package:wheelathlete/state/ble_providers.dart';
import 'package:wheelathlete/theme/theme.dart';
import 'package:wheelathlete/widgets/widgets.dart';

/// Shows a dialog with a single text field pre-filled with [initialValue].
/// Returns the trimmed text the user entered, or null if cancelled.
Future<String?> showTextEditDialog(
  BuildContext context, {
  required String title,
  required String label,
  String? initialValue,
  String? hint,
  int maxLines = 1,
}) {
  final controller = TextEditingController(text: initialValue ?? '');
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        decoration: InputDecoration(labelText: label, hintText: hint),
        autofocus: true,
        maxLines: maxLines,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

/// Browse screen: topic → trial → session hierarchy.
///
/// Three-level navigation:
/// 1. Topic list (all topic folders)
/// 2. Trial list (all trials in a topic)
/// 3. Session list (all sessions in a trial, with share/export buttons)
class BrowsePage extends ConsumerStatefulWidget {
  const BrowsePage({super.key});

  @override
  ConsumerState<BrowsePage> createState() => _BrowsePageState();
}

class _BrowsePageState extends ConsumerState<BrowsePage> {
  String? _selectedTopic;
  int? _selectedTrial;

  @override
  Widget build(BuildContext context) {
    if (_selectedTrial != null && _selectedTopic != null) {
      return _SessionListView(
        topic: _selectedTopic!,
        trialNumber: _selectedTrial!,
        onBack: () => setState(() => _selectedTrial = null),
      );
    }
    if (_selectedTopic != null) {
      return _TrialListView(
        topic: _selectedTopic!,
        onBack: () => setState(() => _selectedTopic = null),
        onTrialTap: (trial) => setState(() => _selectedTrial = trial),
      );
    }
    return _TopicListView(
      onTopicTap: (topic) => setState(() => _selectedTopic = topic),
    );
  }
}

class _TopicListView extends ConsumerStatefulWidget {
  const _TopicListView({required this.onTopicTap});
  final ValueChanged<String> onTopicTap;

  @override
  ConsumerState<_TopicListView> createState() => _TopicListViewState();
}

class _TopicListViewState extends ConsumerState<_TopicListView> {
  Future<List<TopicEntry>>? _future;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _future = ref.read(storageRepositoryProvider).listTopics();
    if (mounted) setState(() {});
  }

  Future<void> _renameTopic(TopicEntry t) async {
    final newName = await showTextEditDialog(
      context,
      title: 'Rename topic',
      label: 'Topic name',
      initialValue: t.name,
    );
    if (newName == null || newName.isEmpty || !mounted) return;
    try {
      await ref.read(storageRepositoryProvider).renameTopic(t.name, newName);
      if (!mounted) return;
      _refresh();
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Rename failed: $e')),
      );
    }
  }

  Future<void> _editDescription(TopicEntry t) async {
    final desc = await showTextEditDialog(
      context,
      title: 'Edit description',
      label: 'Description',
      initialValue: t.description,
      maxLines: 3,
    );
    if (!mounted) return;
    try {
      await ref
          .read(storageRepositoryProvider)
          .updateTopicDescription(t.name, desc);
      if (!mounted) return;
      _refresh();
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Update failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Browse')),
      body: FutureBuilder<List<TopicEntry>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final topics = snapshot.data ?? [];
          if (topics.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.folder_off_rounded,
                      size: 48, color: Theme.of(context).disabledColor),
                  const SizedBox(height: AppSpacing.md),
                  Text('No topics yet',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.xs),
                  Text('Record a session to create your first topic.',
                      style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.md),
            itemCount: topics.length,
            separatorBuilder: (_,_) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, i) {
              final t = topics[i];
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.folder_rounded),
                  title: Text(t.name),
                  subtitle: t.description != null ? Text(t.description!) : null,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PopupMenuButton<String>(
                        tooltip: 'Edit topic',
                        icon: const Icon(Icons.more_vert_rounded),
                        onSelected: (value) {
                          if (value == 'rename') {
                            _renameTopic(t);
                          } else if (value == 'description') {
                            _editDescription(t);
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'rename',
                            child: ListTile(
                              leading: Icon(Icons.drive_file_rename_outline_rounded),
                              title: Text('Rename'),
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'description',
                            child: ListTile(
                              leading: Icon(Icons.edit_note_rounded),
                              title: Text('Edit description'),
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                            ),
                          ),
                        ],
                      ),
                      const Icon(Icons.chevron_right_rounded),
                    ],
                  ),
                  onTap: () => widget.onTopicTap(t.name),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _TrialListView extends ConsumerWidget {
  const _TrialListView({
    required this.topic,
    required this.onBack,
    required this.onTrialTap,
  });
  final String topic;
  final VoidCallback onBack;
  final ValueChanged<int> onTrialTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text(topic),
        leading: IconButton(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      body: FutureBuilder<List<int>>(
        future: ref.read(storageRepositoryProvider).listTrials(topic),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final trials = snapshot.data ?? [];
          if (trials.isEmpty) {
            return Center(
              child: Text('No trials in $topic',
                  style: Theme.of(context).textTheme.bodyMedium),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.md),
            itemCount: trials.length,
            separatorBuilder: (_,_) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, i) {
              final trial = trials[i];
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.layers_rounded),
                  title: Text('trial_${trial.toString().padLeft(2, '0')}'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => onTrialTap(trial),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _SessionListView extends ConsumerStatefulWidget {
  const _SessionListView({
    required this.topic,
    required this.trialNumber,
    required this.onBack,
  });
  final String topic;
  final int trialNumber;
  final VoidCallback onBack;

  @override
  ConsumerState<_SessionListView> createState() => _SessionListViewState();
}

class _SessionListViewState extends ConsumerState<_SessionListView> {
  Future<List<SessionMeta>>? _future;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _future = ref
        .read(storageRepositoryProvider)
        .listSessions(widget.topic, widget.trialNumber);
    if (mounted) setState(() {});
  }

  Future<void> _editSessionMeta(SessionMeta meta) async {
    final notes = await showTextEditDialog(
      context,
      title: 'Edit notes',
      label: 'Notes',
      initialValue: meta.notes,
      maxLines: 4,
    );
    if (!mounted) return;
    final video = await showTextEditDialog(
      context,
      title: 'Video filename',
      label: 'Video file name',
      initialValue: meta.videoFileName,
      hint: 'e.g. run_cam_01.mp4',
    );
    if (!mounted) return;
    try {
      await ref.read(storageRepositoryProvider).updateSessionMeta(
            widget.topic,
            widget.trialNumber,
            meta.sessionId,
            notes: notes,
            videoFile: video,
          );
      if (!mounted) return;
      _refresh();
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Update failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('trial_${widget.trialNumber.toString().padLeft(2, '0')}'),
        leading: IconButton(
          onPressed: widget.onBack,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      body: FutureBuilder<List<SessionMeta>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final sessions = snapshot.data ?? [];
          if (sessions.isEmpty) {
            return Center(
              child: Text('No sessions in trial ${widget.trialNumber}',
                  style: Theme.of(context).textTheme.bodyMedium),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.md),
            itemCount: sessions.length,
            separatorBuilder: (_,_) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, i) {
              final meta = sessions[i];
              final dt = DateTime.fromMillisecondsSinceEpoch(
                  meta.startTime.millisecondsSinceEpoch);
              return SessionListItem(
                title: meta.sessionId,
                subtitle:
                    '${widget.topic} · ${dt.toIso8601String().split('T').first}',
                duration: Duration(milliseconds: meta.durationMs),
                sampleCount: meta.sampleCount,
                markerCount: meta.markerCount,
                syncQuality: meta.driftResidualRmsMsLeft != null
                    ? '±${meta.driftResidualRmsMsLeft!.toStringAsFixed(1)} ms'
                    : null,
                onShare: () => _share(context, meta),
                onEdit: () => _editSessionMeta(meta),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _share(BuildContext context, SessionMeta meta) async {
    // Share is handled by the export provider (subtask #18); here we just show
    // a snackbar placeholder until the export wiring lands.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Sharing ${meta.sessionId}...')),
    );
  }
}

