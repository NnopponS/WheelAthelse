import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wheelathlete/records/session_model.dart';
import 'package:wheelathlete/records/storage_repository.dart';
import 'package:wheelathlete/state/ble_providers.dart';
import 'package:wheelathlete/state/record_countdown_providers.dart';
import 'package:wheelathlete/state/recording_providers.dart';
import 'package:wheelathlete/theme/theme.dart';
import 'package:wheelathlete/widgets/widgets.dart';

/// Recording screen: pick a topic, start/stop recording, and see live sample
/// counts.
///
/// State machine driven by [RecordingNotifier]:
/// - idle: topic picker + "Start Recording" button
/// - recording: live stats + "Stop Recording" button
/// - stopped: "Session saved" + "New Recording" button
class RecordPage extends ConsumerStatefulWidget {
  const RecordPage({super.key});

  @override
  ConsumerState<RecordPage> createState() => _RecordPageState();
}

class _RecordPageState extends ConsumerState<RecordPage> {
  String? _selectedTopic;
  int _trialNumber = 1;
  bool _loadingTopics = true;

  @override
  void initState() {
    super.initState();
    _refreshTopics();
  }

  Future<void> _refreshTopics() async {
    final storage = ref.read(storageRepositoryProvider);
    final topics = await storage.listTopics();
    if (!mounted) return;
    setState(() {
      if (topics.isNotEmpty && _selectedTopic == null) {
        _selectedTopic = topics.first.name;
        _refreshTrialNumber();
      } else if (_selectedTopic != null &&
          !topics.any((t) => t.name == _selectedTopic)) {
        _selectedTopic = topics.isNotEmpty ? topics.first.name : null;
        _refreshTrialNumber();
      }
      _loadingTopics = false;
    });
  }

  Future<void> _refreshTrialNumber() async {
    if (_selectedTopic == null) return;
    final storage = ref.read(storageRepositoryProvider);
    final n = await storage.nextTrialNumber(_selectedTopic!);
    if (!mounted) return;
    setState(() => _trialNumber = n);
  }

  @override
  Widget build(BuildContext context) {
    final rec = ref.watch(recordingProvider);
    final countdown = ref.watch(recordCountdownProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Record')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Countdown states take precedence over the recording state
            // machine while a countdown is in progress.
            switch (countdown.status) {
              RecordCountdownStatus.syncing =>
                _buildSyncingView(context, theme),
              RecordCountdownStatus.counting =>
                _buildCountingView(context, theme, countdown),
              RecordCountdownStatus.error when rec.status == RecordingStatus.idle =>
                _buildCountdownErrorView(context, theme, countdown),
              _ => switch (rec.status) {
                  RecordingStatus.idle => _buildIdleView(context, theme),
                  RecordingStatus.recording =>
                    _buildRecordingView(context, theme, rec),
                  RecordingStatus.stopped =>
                    _buildStoppedView(context, theme, rec),
                },
            },
          ],
        ),
      ),
    );
  }

  Widget _buildSyncingView(BuildContext context, ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 56,
            height: 56,
            child: CircularProgressIndicator(strokeWidth: 4),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Syncing time with both wheels…',
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Estimating clock offset for synchronized start',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildCountingView(
    BuildContext context,
    ThemeData theme,
    RecordCountdownState countdown,
  ) {
    final seconds = countdown.countdownSeconds;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Starting in',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Text(
              '$seconds',
              key: ValueKey(seconds),
              style: theme.textTheme.displayLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Beep 3-2-1 on the M5 speakers',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          FilledButton.tonalIcon(
            onPressed: () => _cancelCountdown(),
            icon: const Icon(Icons.cancel_rounded),
            label: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Widget _buildCountdownErrorView(
    BuildContext context,
    ThemeData theme,
    RecordCountdownState countdown,
  ) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded,
              size: 48, color: theme.colorScheme.error),
          const SizedBox(height: AppSpacing.md),
          Text(
            countdown.error ?? 'Countdown failed',
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            onPressed: () =>
                ref.read(recordCountdownProvider.notifier).reset(),
            child: const Text('Dismiss'),
          ),
        ],
      ),
    );
  }

  Future<void> _cancelCountdown() async {
    try {
      await ref.read(recordCountdownProvider.notifier).cancel();
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cancel failed: $e')),
        );
      }
    }
  }

  Widget _buildIdleView(BuildContext context, ThemeData theme) {
    if (_loadingTopics) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Topic', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        _TopicDropdown(
          selectedTopic: _selectedTopic,
          onChanged: (topic) async {
            setState(() => _selectedTopic = topic);
            await _refreshTrialNumber();
          },
          onRefresh: _refreshTopics,
        ),
        const SizedBox(height: AppSpacing.md),
        if (_selectedTopic != null) ...[
          _TrialInfo(trialNumber: _trialNumber),
          const SizedBox(height: AppSpacing.lg),
          PrimaryActionButton(
            label: 'Start Recording',
            icon: Icons.fiber_manual_record_rounded,
            intent: ActionIntent.start,
            onPressed: _selectedTopic != null
                ? () => _startRecording()
                : null,
          ),
        ] else ...[
          Text(
            'Create a topic first to start recording.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton.tonalIcon(
            onPressed: () => _showNewTopicDialog(context),
            icon: const Icon(Icons.create_new_folder_rounded),
            label: const Text('New Topic'),
          ),
        ],
      ],
    );
  }

  Widget _buildRecordingView(
    BuildContext context,
    ThemeData theme,
    RecordingState rec,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${rec.config?.topic} · trial_${rec.config?.trialNumber.toString().padLeft(2, '0')}',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: [
                    StatusBadge(
                      label: '${rec.sampleCount} samples',
                      icon: Icons.scatter_plot_rounded,
                    ),
                    StatusBadge(
                      label: _elapsedLabel(rec),
                      icon: Icons.timer_outlined,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        PrimaryActionButton(
          label: 'Stop Recording',
          icon: Icons.stop_rounded,
          intent: ActionIntent.stop,
          onPressed: () => _stopRecording(),
        ),
      ],
    );
  }

  Widget _buildStoppedView(
    BuildContext context,
    ThemeData theme,
    RecordingState rec,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.check_circle_rounded,
                        color: theme.colorScheme.primary),
                    const SizedBox(width: AppSpacing.sm),
                    Text('Session saved', style: theme.textTheme.titleMedium),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '${rec.config?.topic} · trial_${rec.config?.trialNumber.toString().padLeft(2, '0')}',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: [
                    StatusBadge(
                      label: '${rec.sampleCount} samples',
                      icon: Icons.scatter_plot_rounded,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        PrimaryActionButton(
          label: 'New Recording',
          icon: Icons.refresh_rounded,
          onPressed: () {
            ref.read(recordingProvider.notifier).reset();
            ref.read(recordCountdownProvider.notifier).reset();
            _refreshTopics();
          },
        ),
      ],
    );
  }

  String _elapsedLabel(RecordingState rec) {
    if (rec.startTime == null) return '0s';
    final elapsed = DateTime.now().difference(rec.startTime!);
    final m = elapsed.inMinutes;
    final s = elapsed.inSeconds % 60;
    return m > 0 ? '${m}m ${s}s' : '${s}s';
  }

  Future<void> _startRecording() async {
    if (_selectedTopic == null) return;
    final config = SessionConfig(
      topic: _selectedTopic!,
      trialNumber: _trialNumber,
      sampleRateHz: 100,
    );
    try {
      await ref.read(recordCountdownProvider.notifier).start(config);
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start: $e')),
        );
      }
    }
  }

  Future<void> _stopRecording() async {
    try {
      await ref.read(recordingProvider.notifier).stopRecording();
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to stop: $e')),
        );
      }
    }
  }

  Future<void> _showNewTopicDialog(BuildContext context) async {
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('New Topic'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Topic name',
              hintText: 'e.g. sprint_test, athlete_A',
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
    if (name == null || name.isEmpty) return;
    try {
      final storage = ref.read(storageRepositoryProvider);
      await storage.createTopic(name);
      setState(() => _selectedTopic = name);
      await _refreshTrialNumber();
    } on Object catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to create topic: $e')),
      );
    }
  }
}

class _TopicDropdown extends ConsumerStatefulWidget {
  const _TopicDropdown({
    required this.selectedTopic,
    required this.onChanged,
    required this.onRefresh,
  });

  final String? selectedTopic;
  final ValueChanged<String?> onChanged;
  final Future<void> Function() onRefresh;

  @override
  ConsumerState<_TopicDropdown> createState() => _TopicDropdownState();
}

class _TopicDropdownState extends ConsumerState<_TopicDropdown> {
  Future<List<TopicEntry>>? _topicsFuture;

  @override
  void initState() {
    super.initState();
    _loadTopics();
  }

  void _loadTopics() {
    _topicsFuture = ref.read(storageRepositoryProvider).listTopics();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<TopicEntry>>(
      future: _topicsFuture,
      builder: (context, snapshot) {
        final topics = snapshot.data ?? [];
        return Row(
          children: [
            Expanded(
              child: DropdownButton<String>(
                value: widget.selectedTopic,
                hint: const Text('Select topic'),
                isExpanded: true,
                items: topics
                    .map((t) => DropdownMenuItem(
                          value: t.name,
                          child: Text(t.name),
                        ))
                    .toList(),
                onChanged: widget.onChanged,
              ),
            ),
            IconButton(
              onPressed: () =>
                  showDialog<void>(context: context, builder: (ctx) => _NewTopicDialog(onCreated: () { Navigator.pop(ctx); widget.onRefresh(); })),
              icon: const Icon(Icons.create_new_folder_rounded),
              tooltip: 'New Topic',
            ),
          ],
        );
      },
    );
  }
}

class _NewTopicDialog extends ConsumerStatefulWidget {
  const _NewTopicDialog({required this.onCreated});
  final VoidCallback onCreated;

  @override
  ConsumerState<_NewTopicDialog> createState() => _NewTopicDialogState();
}

class _NewTopicDialogState extends ConsumerState<_NewTopicDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New Topic'),
      content: TextField(
        controller: _controller,
        decoration: const InputDecoration(
          labelText: 'Topic name',
          hintText: 'e.g. sprint_test, athlete_A',
        ),
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () async {
            final name = _controller.text.trim();
            if (name.isEmpty) return;
            try {
              await ref.read(storageRepositoryProvider).createTopic(name);
              widget.onCreated();
            } on Object catch (e) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Failed: $e')),
              );
            }
          },
          child: const Text('Create'),
        ),
      ],
    );
  }
}

class _TrialInfo extends StatelessWidget {
  const _TrialInfo({required this.trialNumber});
  final int trialNumber;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(Icons.folder_open_rounded, color: theme.colorScheme.primary),
        const SizedBox(width: AppSpacing.sm),
        Text(
          'trial_${trialNumber.toString().padLeft(2, '0')}',
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(
          '(auto)',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
