import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wheelathlete/records/session_model.dart';
import 'package:wheelathlete/records/storage_repository.dart';
import 'package:wheelathlete/state/ble_providers.dart';
import 'package:wheelathlete/theme/theme.dart';
import 'package:wheelathlete/widgets/widgets.dart';

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

class _TopicListView extends ConsumerWidget {
  const _TopicListView({required this.onTopicTap});
  final ValueChanged<String> onTopicTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Browse')),
      body: FutureBuilder<List<TopicEntry>>(
        future: ref.read(storageRepositoryProvider).listTopics(),
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
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => onTopicTap(t.name),
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

class _SessionListView extends ConsumerWidget {
  const _SessionListView({
    required this.topic,
    required this.trialNumber,
    required this.onBack,
  });
  final String topic;
  final int trialNumber;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text('trial_${trialNumber.toString().padLeft(2, '0')}'),
        leading: IconButton(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      body: FutureBuilder<List<SessionMeta>>(
        future:
            ref.read(storageRepositoryProvider).listSessions(topic, trialNumber),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final sessions = snapshot.data ?? [];
          if (sessions.isEmpty) {
            return Center(
              child: Text('No sessions in trial $trialNumber',
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
                    '$topic · ${dt.toIso8601String().split('T').first}',
                duration: Duration(milliseconds: meta.durationMs),
                sampleCount: meta.sampleCount,
                markerCount: meta.markerCount,
                syncQuality: meta.driftResidualRmsMsLeft != null
                    ? '±${meta.driftResidualRmsMsLeft!.toStringAsFixed(1)} ms'
                    : null,
                onShare: () => _share(context, ref, meta),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _share(
    BuildContext context,
    WidgetRef ref,
    SessionMeta meta,
  ) async {
    // Share is handled by the export provider; here we just show a snackbar
    // since share_plus requires a real platform.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Sharing ${meta.sessionId}...')),
    );
  }
}

