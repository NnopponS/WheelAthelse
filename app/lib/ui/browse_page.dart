import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wheelathlete/export/export_actions.dart';
import 'package:wheelathlete/export/export_providers.dart';
import 'package:wheelathlete/records/quality_badge.dart';
import 'package:wheelathlete/records/session_model.dart';
import 'package:wheelathlete/records/storage_repository.dart';
import 'package:wheelathlete/state/ble_providers.dart';
import 'package:wheelathlete/state/browse_providers.dart';
import 'package:wheelathlete/theme/theme.dart';
import 'package:wheelathlete/ui/tag_editor_dialog.dart';
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

/// Shows a destructive-action confirmation dialog with a red warning icon
/// and [message]. Returns true if the user confirms, false (or null) otherwise.
Future<bool> showDeleteConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.warning_amber_rounded,
          color: Colors.red, size: 40),
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.red,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Empty state shown when a search/filter yields no results but the
/// underlying list was not empty.
class _NoResultsState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off_rounded,
              size: 48, color: Theme.of(context).disabledColor),
          const SizedBox(height: AppSpacing.md),
          Text('No results',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text('Try a different search or clear the filter.',
              style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

/// A fixed search bar shown below the AppBar on Browse list views.
///
/// Wires a [TextField] to [browseSearchProvider] with a search icon prefix
/// and a clear button when the query is non-empty. Filtering is in-memory on
/// the already-loaded list (no storage change).
class _SearchBar extends ConsumerStatefulWidget {
  const _SearchBar({this.hintText = 'Search'});

  final String hintText;

  @override
  ConsumerState<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends ConsumerState<_SearchBar> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: ref.read(browseSearchProvider),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: TextField(
        controller: _controller,
        onChanged: (value) =>
            ref.read(browseSearchProvider.notifier).set(value),
        decoration: InputDecoration(
          hintText: widget.hintText,
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: _controller.text.isNotEmpty
              ? IconButton(
                  onPressed: () {
                    _controller.clear();
                    ref.read(browseSearchProvider.notifier).clear();
                  },
                  icon: const Icon(Icons.clear_rounded),
                )
              : null,
          border: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(AppRadius.lg)),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
        ),
      ),
    );
  }
}

/// Horizontal scrollable row of [FilterChip]s showing all unique tags across
/// the current session list. Tapping a chip toggles [browseTagFilterProvider]
/// between the tag and `null` (tap again to clear).
class _TagFilterChips extends ConsumerWidget {
  const _TagFilterChips({required this.tags});

  final List<String> tags;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(browseTagFilterProvider);
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        itemCount: tags.length,
        separatorBuilder: (_,_) => const SizedBox(width: AppSpacing.xs),
        itemBuilder: (context, i) {
          final tag = tags[i];
          return FilterChip(
            label: Text(tag),
            selected: selected == tag,
            onSelected: (value) {
              ref.read(browseTagFilterProvider.notifier).toggle(tag);
            },
          );
        },
      ),
    );
  }
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
  void initState() {
    super.initState();
    // Consume a pending topic set by the Experiment tracker dashboard (Phase 3,
    // §8) on the first frame (e.g. when the app starts with a pending topic).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final pending = ref.read(selectedTopicProvider);
      if (pending != null) {
        ref.read(selectedTopicProvider.notifier).clear();
        setState(() => _selectedTopic = pending);
      }
    });
  }

  void _resetSearch() {
    ref.read(browseSearchProvider.notifier).clear();
    ref.read(browseTagFilterProvider.notifier).clear();
  }

  @override
  Widget build(BuildContext context) {
    // Listen for cross-tab navigation from the Experiment tracker. Because
    // BrowsePage stays alive inside IndexedStack, this listener fires even when
    // the Browse tab is not currently visible — pre-selecting the topic so it's
    // ready when the user switches over.
    ref.listen<String?>(selectedTopicProvider, (previous, next) {
      if (next != null && next != _selectedTopic) {
        ref.read(selectedTopicProvider.notifier).clear();
        _resetSearch();
        setState(() {
          _selectedTopic = next;
          _selectedTrial = null;
        });
      }
    });

    if (_selectedTrial != null && _selectedTopic != null) {
      return _SessionListView(
        topic: _selectedTopic!,
        trialNumber: _selectedTrial!,
        onBack: () {
          _resetSearch();
          setState(() => _selectedTrial = null);
        },
      );
    }
    if (_selectedTopic != null) {
      return _TrialListView(
        topic: _selectedTopic!,
        onBack: () {
          _resetSearch();
          setState(() => _selectedTopic = null);
        },
        onTrialTap: (trial) {
          _resetSearch();
          setState(() => _selectedTrial = trial);
        },
      );
    }
    return _TopicListView(
      onTopicTap: (topic) {
        _resetSearch();
        setState(() => _selectedTopic = topic);
      },
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

  Future<void> _deleteTopic(TopicEntry t) async {
    final repo = ref.read(storageRepositoryProvider);
    final trials = await repo.listTrials(t.name);
    var sessionCount = 0;
    for (final trial in trials) {
      sessionCount += (await repo.listSessions(t.name, trial)).length;
    }
    if (!mounted) return;
    final confirmed = await showDeleteConfirmDialog(
      context,
      title: "Delete topic '${t.name}'?",
      message: 'This will remove ${trials.length} '
          '${trials.length == 1 ? 'trial' : 'trials'} and '
          '$sessionCount ${sessionCount == 1 ? 'session' : 'sessions'}. '
          'This cannot be undone.',
    );
    if (!confirmed || !mounted) return;
    try {
      await repo.deleteTopic(t.name);
      if (!mounted) return;
      _refresh();
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final searchQuery = ref.watch(browseSearchProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Browse')),
      body: FutureBuilder<List<TopicEntry>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final allTopics = snapshot.data ?? [];
          if (allTopics.isEmpty) {
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
          // In-memory filter by name (case-insensitive substring).
          final q = searchQuery.toLowerCase();
          final topics = q.isEmpty
              ? allTopics
              : allTopics
                  .where((t) => t.name.toLowerCase().contains(q))
                  .toList();
          if (topics.isEmpty) {
            return Column(
              children: [
                const _SearchBar(hintText: 'Search topics'),
                Expanded(child: _NoResultsState()),
              ],
            );
          }
          return Column(
            children: [
              const _SearchBar(hintText: 'Search topics'),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
                  itemCount: topics.length,
                  separatorBuilder: (_,_) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, i) {
                    final t = topics[i];
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.folder_rounded),
                        title: Text(t.name),
                        subtitle: t.description != null
                            ? Text(t.description!)
                            : null,
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
                                } else if (value == 'delete') {
                                  _deleteTopic(t);
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'rename',
                                  child: ListTile(
                                    leading:
                                        Icon(Icons.drive_file_rename_outline_rounded),
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
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: ListTile(
                                    leading: Icon(Icons.delete_outline_rounded,
                                        color: Colors.red),
                                    title: Text('Delete',
                                        style: TextStyle(color: Colors.red)),
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
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TrialListView extends ConsumerStatefulWidget {
  const _TrialListView({
    required this.topic,
    required this.onBack,
    required this.onTrialTap,
  });
  final String topic;
  final VoidCallback onBack;
  final ValueChanged<int> onTrialTap;

  @override
  ConsumerState<_TrialListView> createState() => _TrialListViewState();
}

class _TrialListViewState extends ConsumerState<_TrialListView> {
  Future<List<int>>? _future;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _future = ref.read(storageRepositoryProvider).listTrials(widget.topic);
    if (mounted) setState(() {});
  }

  Future<void> _deleteTrial(int trialNumber) async {
    final repo = ref.read(storageRepositoryProvider);
    final sessions = await repo.listSessions(widget.topic, trialNumber);
    if (!mounted) return;
    final confirmed = await showDeleteConfirmDialog(
      context,
      title: 'Delete trial_${trialNumber.toString().padLeft(2, '0')}?',
      message: 'This will remove ${sessions.length} '
          '${sessions.length == 1 ? 'session' : 'sessions'}. '
          'This cannot be undone.',
    );
    if (!confirmed || !mounted) return;
    try {
      await repo.deleteTrial(widget.topic, trialNumber);
      if (!mounted) return;
      _refresh();
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
      );
    }
  }

  Future<void> _shareTopic(BuildContext context) async {
    final actions = ref.read(exportActionsProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await actions.share(level: ExportLevel.topic, topic: widget.topic);
    } on Object catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Share failed: $e')));
    }
  }

  Future<void> _saveTopicToDevice(BuildContext context) async {
    final actions = ref.read(exportActionsProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final written = await actions.saveToDevice(
        level: ExportLevel.topic,
        topic: widget.topic,
        pickDirectory: pickDirectory,
        writeFile: writeCsvFile,
      );
      if (!mounted) return;
      if (written.isEmpty) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Saved ${written.length} file(s) to device')),
      );
    } on Object catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Save failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final exportState = ref.watch(exportProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.topic),
        leading: IconButton(
          onPressed: widget.onBack,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        actions: [
          IconButton(
            onPressed: exportState.isExporting
                ? null
                : () => _shareTopic(context),
            icon: const Icon(Icons.ios_share_rounded),
            tooltip: 'Share topic',
          ),
          IconButton(
            onPressed: exportState.isExporting
                ? null
                : () => _saveTopicToDevice(context),
            icon: const Icon(Icons.save_alt_rounded),
            tooltip: 'Save topic to device',
          ),
        ],
      ),
      body: FutureBuilder<List<int>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final trials = snapshot.data ?? [];
          if (trials.isEmpty) {
            return Center(
              child: Text('No trials in ${widget.topic}',
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
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PopupMenuButton<String>(
                        tooltip: 'Trial actions',
                        icon: const Icon(Icons.more_vert_rounded),
                        onSelected: (value) {
                          if (value == 'delete') {
                            _deleteTrial(trial);
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'delete',
                            child: ListTile(
                              leading: Icon(Icons.delete_outline_rounded,
                                  color: Colors.red),
                              title: Text('Delete',
                                  style: TextStyle(color: Colors.red)),
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                            ),
                          ),
                        ],
                      ),
                      const Icon(Icons.chevron_right_rounded),
                    ],
                  ),
                  onTap: () => widget.onTrialTap(trial),
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

  Future<void> _editTags(SessionMeta meta) async {
    final updated = await showTagEditorDialog(
      context,
      initialTags: meta.tags,
    );
    if (updated == null || !mounted) return;
    try {
      await ref.read(storageRepositoryProvider).updateSessionTags(
            widget.topic,
            widget.trialNumber,
            meta.sessionId,
            updated,
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

  Future<void> _deleteSession(SessionMeta meta) async {
    final confirmed = await showDeleteConfirmDialog(
      context,
      title: "Delete session '${meta.sessionId}'?",
      message: 'This will permanently remove the session and its CSV data. '
          'This cannot be undone.',
    );
    if (!confirmed || !mounted) return;
    try {
      await ref.read(storageRepositoryProvider).deleteSession(
            widget.topic,
            widget.trialNumber,
            meta.sessionId,
          );
      if (!mounted) return;
      _refresh();
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
      );
    }
  }

  Future<void> _shareSession(SessionMeta meta) async {
    final actions = ref.read(exportActionsProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await actions.share(
        level: ExportLevel.session,
        topic: widget.topic,
        trialNumber: widget.trialNumber,
        sessionId: meta.sessionId,
      );
    } on Object catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Share failed: $e')));
    }
  }

  Future<void> _saveSessionToDevice(SessionMeta meta) async {
    final actions = ref.read(exportActionsProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final written = await actions.saveToDevice(
        level: ExportLevel.session,
        topic: widget.topic,
        trialNumber: widget.trialNumber,
        sessionId: meta.sessionId,
        pickDirectory: pickDirectory,
        writeFile: writeCsvFile,
      );
      if (!mounted) return;
      if (written.isEmpty) return; // user cancelled
      messenger.showSnackBar(
        SnackBar(content: Text('Saved ${written.length} file(s) to device')),
      );
    } on Object catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Save failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final exportState = ref.watch(exportProvider);
    final searchQuery = ref.watch(browseSearchProvider);
    final tagFilter = ref.watch(browseTagFilterProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text('trial_${widget.trialNumber.toString().padLeft(2, '0')}'),
        leading: IconButton(
          onPressed: widget.onBack,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        actions: [
          IconButton(
            onPressed: exportState.isExporting
                ? null
                : () => _shareTrial(context),
            icon: const Icon(Icons.ios_share_rounded),
            tooltip: 'Share trial',
          ),
          IconButton(
            onPressed: exportState.isExporting
                ? null
                : () => _saveTrialToDevice(context),
            icon: const Icon(Icons.save_alt_rounded),
            tooltip: 'Save trial to device',
          ),
        ],
      ),
      body: FutureBuilder<List<SessionMeta>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final allSessions = snapshot.data ?? [];
          if (allSessions.isEmpty) {
            return Center(
              child: Text('No sessions in trial ${widget.trialNumber}',
                  style: Theme.of(context).textTheme.bodyMedium),
            );
          }
          // Collect unique tags across the current (unfiltered) session list.
          final allTags = <String>{};
          for (final s in allSessions) {
            allTags.addAll(s.tags);
          }
          final sortedTags = allTags.toList()..sort();

          // In-memory filter: search (ID, notes, date ISO, tags) AND tag filter.
          final q = searchQuery.toLowerCase();
          final sessions = allSessions.where((meta) {
            final matchesSearch = q.isEmpty ||
                meta.sessionId.toLowerCase().contains(q) ||
                (meta.notes?.toLowerCase().contains(q) ?? false) ||
                meta.startTime.toIso8601String().toLowerCase().contains(q) ||
                meta.tags.any((t) => t.toLowerCase().contains(q));
            final matchesTag =
                tagFilter == null || meta.tags.contains(tagFilter);
            return matchesSearch && matchesTag;
          }).toList();

          if (sessions.isEmpty) {
            return Column(
              children: [
                const _SearchBar(hintText: 'Search sessions'),
                if (sortedTags.isNotEmpty) _TagFilterChips(tags: sortedTags),
                Expanded(child: _NoResultsState()),
              ],
            );
          }
          return Column(
            children: [
              const _SearchBar(hintText: 'Search sessions'),
              if (sortedTags.isNotEmpty) _TagFilterChips(tags: sortedTags),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
                  itemCount: sessions.length,
                  separatorBuilder: (_,_) =>
                      const SizedBox(height: AppSpacing.sm),
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
                      qualityLevel: QualityBadge.fromMeta(meta),
                      tags: meta.tags,
                      onShare: exportState.isExporting
                          ? null
                          : () => _shareSession(meta),
                      onSave: exportState.isExporting
                          ? null
                          : () => _saveSessionToDevice(meta),
                      onEdit: () => _editSessionMeta(meta),
                      onEditTags: () => _editTags(meta),
                      onDelete: () => _deleteSession(meta),
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

  Future<void> _shareTrial(BuildContext context) async {
    final actions = ref.read(exportActionsProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await actions.share(
        level: ExportLevel.trial,
        topic: widget.topic,
        trialNumber: widget.trialNumber,
      );
    } on Object catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Share failed: $e')));
    }
  }

  Future<void> _saveTrialToDevice(BuildContext context) async {
    final actions = ref.read(exportActionsProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final written = await actions.saveToDevice(
        level: ExportLevel.trial,
        topic: widget.topic,
        trialNumber: widget.trialNumber,
        pickDirectory: pickDirectory,
        writeFile: writeCsvFile,
      );
      if (!mounted) return;
      if (written.isEmpty) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Saved ${written.length} file(s) to device')),
      );
    } on Object catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Save failed: $e')));
    }
  }
}

