import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wheelathlete/records/protocol_template.dart';
import 'package:wheelathlete/records/quality_badge.dart';
import 'package:wheelathlete/records/session_model.dart';
import 'package:wheelathlete/records/storage_repository.dart';
import 'package:wheelathlete/state/ble_providers.dart';
import 'package:wheelathlete/state/browse_providers.dart';
import 'package:wheelathlete/state/home_providers.dart';
import 'package:wheelathlete/state/imu_providers.dart';
import 'package:wheelathlete/state/live_acquisition_providers.dart';
import 'package:wheelathlete/state/model_management_providers.dart';
import 'package:wheelathlete/state/protocol_providers.dart';
import 'package:wheelathlete/state/record_countdown_providers.dart';
import 'package:wheelathlete/state/recording_providers.dart';
import 'package:wheelathlete/state/sync_providers.dart';
import 'package:wheelathlete/theme/theme.dart';
import 'package:wheelathlete/widgets/widgets.dart';

/// Unified Acquisition Page:
/// - Realtime 3-IMU streaming preview (Left, Right, Chair Center)
/// - Synchronized recording with 5-second countdown & clock sync
/// - 3-sensor telemetry metrics cards (L, R, C)
/// - 6 Realtime waveform charts (L Accel/Gyro, R Accel/Gyro, C Accel/Gyro)
/// - Post-recording QC summary card & seamless routing into Model inference
class AcquisitionPage extends ConsumerStatefulWidget {
  const AcquisitionPage({super.key});

  @override
  ConsumerState<AcquisitionPage> createState() => _AcquisitionPageState();
}

class _AcquisitionPageState extends ConsumerState<AcquisitionPage> {
  String? _selectedTopic;
  int _trialNumber = 1;
  String? _selectedTemplateId;
  int _sampleRateHz = 100;
  WheelSide? _selectedChartSide;

  @override
  void initState() {
    super.initState();
    _refreshTopics();
  }

  Future<void> _refreshTopics() async {
    ref.invalidate(topicsProvider);
  }

  Future<void> _refreshTrialNumber() async {
    if (_selectedTopic == null) return;
    final storage = ref.read(storageRepositoryProvider);
    final n = await storage.nextTrialNumber(_selectedTopic!);
    if (!mounted) return;
    setState(() => _trialNumber = n);
  }

  Future<void> _onTemplateSelected(
    String? id,
    List<ProtocolTemplate> templates,
  ) async {
    if (id == null) {
      setState(() {
        _selectedTemplateId = null;
        _sampleRateHz = 100;
      });
      await _refreshTopics();
      return;
    }
    final template = templates.firstWhere((t) => t.id == id);
    final storage = ref.read(storageRepositoryProvider);
    final topics = await storage.listTopics();
    if (!topics.any((t) => t.name == template.topicName)) {
      try {
        await storage.createTopic(template.topicName);
      } on StateError {
        // Topic already exists
      }
    }
    if (!mounted) return;
    setState(() {
      _selectedTemplateId = id;
      _selectedTopic = template.topicName;
      _sampleRateHz = template.sampleRateHz;
    });
    await _refreshTrialNumber();
  }

  Future<bool> _confirmSingleWheelIfNeeded() async {
    final connections = ref.read(connectionManagerProvider);
    final connected = WheelSide.values
        .where((s) => connections.bySide[s]!.status == ConnectionStatus.connected)
        .toList();
    if (connected.length != 1) return true;
    final side = connected.single.shortLabel;
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Only one sensor connected'),
            content: Text(
              '$side is connected. Continue with single-sensor recording?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Continue'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _startRecording() async {
    if (_selectedTopic == null) return;
    if (!await _confirmSingleWheelIfNeeded()) return;
    final config = SessionConfig(
      topic: _selectedTopic!,
      trialNumber: _trialNumber,
      sampleRateHz: _sampleRateHz,
      protocolTemplateId: _selectedTemplateId,
    );
    try {
      await ref.read(recordCountdownProvider.notifier).start(config);
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start recording: $e')),
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
          SnackBar(content: Text('Failed to stop recording: $e')),
        );
      }
    }
  }

  Future<void> _showNewTopicDialog() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Topic'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Topic name',
            hintText: 'e.g. 100m_sprint, slalom_v3',
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
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      final storage = ref.read(storageRepositoryProvider);
      await storage.createTopic(name);
      if (!mounted) return;
      setState(() => _selectedTopic = name);
      await _refreshTrialNumber();
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to create topic: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<List<TopicEntry>>>(topicsProvider, (prev, next) {
      next.whenData((topics) {
        if (topics.isNotEmpty && _selectedTopic == null) {
          setState(() => _selectedTopic = topics.first.name);
          _refreshTrialNumber();
        } else if (_selectedTopic != null && !topics.any((t) => t.name == _selectedTopic)) {
          setState(() => _selectedTopic = topics.isNotEmpty ? topics.first.name : null);
          _refreshTrialNumber();
        }
      });
    });

    final connState = ref.watch(connectionManagerProvider);
    final anyConnected = connState.bySide.values.any((c) => c.status == ConnectionStatus.connected);
    final live = ref.watch(liveAcquisitionProvider);
    final recStatus = ref.watch(recordingProvider.select((s) => s.status));
    final countdown = ref.watch(recordCountdownProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Acquisition'),
        actions: [
          IconButton(
            tooltip: 'Sync sensor clocks',
            icon: const Icon(Icons.sync_rounded),
            onPressed: anyConnected
                ? () async {
                    for (final s in WheelSide.values) {
                      final conn = ref.read(connectionManagerProvider).bySide[s];
                      if (conn?.status == ConnectionStatus.connected) {
                        await ref.read(syncEngineProvider.notifier).synchronize(s, count: 5);
                      }
                    }
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Sensor clocks synchronized.')),
                      );
                    }
                  }
                : null,
          ),
          IconButton(
            tooltip: 'Go to Results',
            icon: const Icon(Icons.folder_rounded),
            onPressed: () => ref.read(homeTabIndexProvider.notifier).setTab(HomeTabNotifier.results),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          // Section 1: Live Stream Preview Controls
          _buildLiveStreamCard(context, live, anyConnected),
          const SizedBox(height: AppSpacing.md),

          // Section 2: Recording Workflow (Countdown, Active Recording, Stopped QC, or Setup)
          _buildRecordingSection(context, recStatus, countdown),
          const SizedBox(height: AppSpacing.md),

          // Section 3: 3-IMU Sensor Readouts (L, R, C)
          Text(
            'Sensor Readouts (3-IMU)',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: AppSpacing.sm),
          const _SensorReadoutGrid(),
          const SizedBox(height: AppSpacing.lg),

          // Section 4: 6 Realtime Waveform Charts
          Row(
            children: [
              Expanded(
                child: Text(
                  'Realtime Waveforms',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              SegmentedButton<WheelSide?>(
                segments: const [
                  ButtonSegment(value: null, label: Text('All')),
                  ButtonSegment(value: WheelSide.left, label: Text('L')),
                  ButtonSegment(value: WheelSide.right, label: Text('R')),
                  ButtonSegment(value: WheelSide.center, label: Text('C')),
                ],
                selected: {_selectedChartSide},
                onSelectionChanged: (set) => setState(() => _selectedChartSide = set.first),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _buildWaveformCharts(context),
        ],
      ),
    );
  }

  Widget _buildLiveStreamCard(BuildContext context, LiveAcquisitionState live, bool anyConnected) {
    final theme = Theme.of(context);
    final isStreaming = live.active;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Icon(
              isStreaming ? Icons.sensors_rounded : Icons.sensors_off_rounded,
              color: isStreaming ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
              size: 28,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isStreaming ? 'Live Preview Active' : 'Live Preview Paused',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    anyConnected
                        ? (isStreaming ? 'Streaming IMU telemetry from sensors' : 'Ready to preview IMU channels')
                        : 'Connect sensors in Dashboard first',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: anyConnected && live.canToggle
                  ? () => isStreaming
                      ? ref.read(liveAcquisitionProvider.notifier).stop()
                      : ref.read(liveAcquisitionProvider.notifier).start()
                  : null,
              icon: Icon(isStreaming ? Icons.pause_rounded : Icons.play_arrow_rounded),
              label: Text(isStreaming ? 'Pause' : 'Start Preview'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordingSection(
    BuildContext context,
    RecordingStatus recStatus,
    RecordCountdownState countdown,
  ) {
    if (countdown.status == RecordCountdownStatus.syncing) {
      return _buildSyncingCard(context);
    }
    if (countdown.status == RecordCountdownStatus.counting) {
      return _buildCountingCard(context, countdown.countdownSeconds);
    }
    if (countdown.status == RecordCountdownStatus.error) {
      return _buildCountdownErrorCard(context, countdown.error);
    }

    return switch (recStatus) {
      RecordingStatus.recording ||
      RecordingStatus.arming ||
      RecordingStatus.awaitingSamples ||
      RecordingStatus.stopping =>
        _buildActiveRecordingCard(context, recStatus),
      RecordingStatus.stopped => _buildStoppedQcCard(context),
      RecordingStatus.failed => _buildRecordingFailedCard(context),
      RecordingStatus.idle => _buildRecordingSetupCard(context),
    };
  }

  Widget _buildSyncingCard(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: const Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            SizedBox(
              width: 44,
              height: 44,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            SizedBox(height: AppSpacing.md),
            Text('Synchronizing sensor clocks…', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: AppSpacing.xs),
            Text('Aligning timestamps for 3-IMU capture'),
          ],
        ),
      ),
    );
  }

  Widget _buildCountingCard(BuildContext context, int seconds) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            Text('Synchronized Start in', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: Text(
                '$seconds',
                key: ValueKey(seconds),
                style: theme.textTheme.displayLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.tonalIcon(
              onPressed: () => ref.read(recordCountdownProvider.notifier).cancel(),
              icon: const Icon(Icons.close_rounded),
              label: const Text('Cancel Countdown'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCountdownErrorCard(BuildContext context, String? error) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          children: [
            Icon(Icons.error_outline_rounded, color: theme.colorScheme.onErrorContainer, size: 36),
            const SizedBox(height: AppSpacing.xs),
            Text(
              error ?? 'Countdown failed',
              style: TextStyle(color: theme.colorScheme.onErrorContainer),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            FilledButton.tonal(
              onPressed: () => ref.read(recordCountdownProvider.notifier).reset(),
              child: const Text('Dismiss'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveRecordingCard(BuildContext context, RecordingStatus status) {
    final theme = Theme.of(context);
    final rec = ref.watch(recordingProvider);
    final config = rec.config;

    return Card(
      color: theme.colorScheme.errorContainer.withAlpha(50),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.fiber_manual_record_rounded, color: Colors.red, size: 20),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  'RECORDING: ${config?.topic ?? ""} · Trial ${config?.trialNumber ?? 1}',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text(
                  '${rec.sampleCount} pts',
                  style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            LinearProgressIndicator(color: theme.colorScheme.error),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
              onPressed: status == RecordingStatus.stopping ? null : _stopRecording,
              icon: const Icon(Icons.stop_rounded),
              label: Text(status == RecordingStatus.stopping ? 'Stopping…' : 'Stop & Finalize Session'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStoppedQcCard(BuildContext context) {
    final theme = Theme.of(context);
    final rec = ref.watch(recordingProvider);
    final meta = rec.lastMeta;

    return Card(
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.green, size: 24),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'Session Recorded & Validated',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Session ID: ${meta?.sessionId ?? "Unknown"}',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                Chip(
                  avatar: const Icon(Icons.scatter_plot_rounded, size: 16),
                  label: Text('${meta?.sampleCount ?? rec.sampleCount} samples'),
                ),
                Chip(
                  avatar: const Icon(Icons.speed_rounded, size: 16),
                  label: Text('${meta?.sampleRateHz ?? 100} Hz target'),
                ),
                Chip(
                  avatar: const Icon(Icons.high_quality_rounded, size: 16),
                  label: Text('QC: ${meta != null ? QualityBadge.fromMeta(meta).name : "good"}'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      ref.read(recordingProvider.notifier).reset();
                      ref.read(recordCountdownProvider.notifier).reset();
                      _refreshTrialNumber();
                    },
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('New Recording'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                if (meta != null)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        ref.read(selectedModelSessionIdProvider.notifier).set(meta.sessionId);
                        ref.read(homeTabIndexProvider.notifier).setTab(HomeTabNotifier.model);
                      },
                      icon: const Icon(Icons.route_rounded),
                      label: const Text('Open in Model'),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordingFailedCard(BuildContext context) {
    final theme = Theme.of(context);
    final rec = ref.watch(recordingProvider);
    return Card(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          children: [
            Icon(Icons.error_outline_rounded, color: theme.colorScheme.onErrorContainer, size: 36),
            const SizedBox(height: AppSpacing.xs),
            Text('Recording failed: ${rec.error ?? "Unknown error"}'),
            const SizedBox(height: AppSpacing.sm),
            FilledButton.tonal(
              onPressed: () {
                ref.read(recordingProvider.notifier).reset();
                ref.read(recordCountdownProvider.notifier).reset();
              },
              child: const Text('Reset'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordingSetupCard(BuildContext context) {
    final theme = Theme.of(context);
    final templatesAsync = ref.watch(protocolTemplatesProvider);
    final topicsAsync = ref.watch(topicsProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.tune_rounded, color: theme.colorScheme.primary),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  'Recording Configuration',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            // Protocols / Templates chips
            templatesAsync.when(
              data: (templates) => Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  ChoiceChip(
                    label: const Text('Custom'),
                    selected: _selectedTemplateId == null,
                    onSelected: (sel) {
                      if (sel) _onTemplateSelected(null, templates);
                    },
                  ),
                  ...templates.map(
                    (t) => ChoiceChip(
                      label: Text(t.name),
                      selected: _selectedTemplateId == t.id,
                      onSelected: (sel) => _onTemplateSelected(sel ? t.id : null, templates),
                    ),
                  ),
                ],
              ),
              loading: () => const LinearProgressIndicator(),
              error: (_, _) => const SizedBox.shrink(),
            ),
            const SizedBox(height: AppSpacing.sm),
            // Topic selection
            Row(
              children: [
                Expanded(
                  child: topicsAsync.when(
                    data: (topics) => DropdownButtonFormField<String>(
                      initialValue: _selectedTopic != null && topics.any((t) => t.name == _selectedTopic)
                          ? _selectedTopic
                          : null,
                      decoration: const InputDecoration(
                        labelText: 'Topic / Experiment',
                        contentPadding: EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                      ),
                      items: topics
                          .map((t) => DropdownMenuItem(value: t.name, child: Text(t.name)))
                          .toList(),
                      onChanged: (val) {
                        setState(() => _selectedTopic = val);
                        _refreshTrialNumber();
                      },
                    ),
                    loading: () => const LinearProgressIndicator(),
                    error: (_, _) => const Text('Error loading topics'),
                  ),
                ),
                IconButton(
                  tooltip: 'New Topic',
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  onPressed: _showNewTopicDialog,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            // Trial number & Sample rate
            Row(
              children: [
                Expanded(
                  child: Text('Trial: #$_trialNumber', style: theme.textTheme.bodyMedium),
                ),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 50, label: Text('50Hz')),
                    ButtonSegment(value: 100, label: Text('100Hz')),
                    ButtonSegment(value: 200, label: Text('200Hz')),
                  ],
                  selected: {_sampleRateHz},
                  onSelectionChanged: (set) => setState(() => _sampleRateHz = set.first),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              onPressed: _selectedTopic != null ? _startRecording : null,
              icon: const Icon(Icons.fiber_manual_record_rounded),
              label: const Text('Start Synchronized Recording'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWaveformCharts(BuildContext context) {
    final imuState = ref.watch(imuStreamProvider);
    final wc = context.wheelColors;

    final sidesToPlot = _selectedChartSide != null
        ? [_selectedChartSide!]
        : [WheelSide.left, WheelSide.right, WheelSide.center];

    return Column(
      children: sidesToPlot.map((side) {
        final wheelData = imuState.bySide[side]!;
        final role = wc.forWheel(side);
        final axisColors = [role.solid, wc.success.solid, wc.warning.solid];

        return Card(
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    StatusBadge(
                      label: side.shortLabel,
                      tone: switch (side) {
                        WheelSide.left => BadgeTone.left,
                        WheelSide.right => BadgeTone.right,
                        WheelSide.center => BadgeTone.center,
                      },
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      '${side.deviceLabel} (${wheelData.sampleCount} pts)',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const Spacer(),
                    Text(
                      'X: Accel (g) / Y: Gyro (°/s)',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                // Accelerometer Waveform Chart
                Text('Accelerometer (ax, ay, az)', style: Theme.of(context).textTheme.labelSmall),
                SizedBox(
                  height: 110,
                  child: ImuChart(
                    readings: wheelData.recent,
                    isAccel: true,
                    axisColors: axisColors,
                    height: 110,
                  ),
                ),
                const Divider(height: AppSpacing.sm),
                // Gyroscope Waveform Chart
                Text('Gyroscope (gx, gy, gz)', style: Theme.of(context).textTheme.labelSmall),
                SizedBox(
                  height: 110,
                  child: ImuChart(
                    readings: wheelData.recent,
                    isAccel: false,
                    axisColors: axisColors,
                    height: 110,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _SensorReadoutGrid extends ConsumerWidget {
  const _SensorReadoutGrid();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const Column(
      children: [
        _SensorReadoutCard(side: WheelSide.left),
        SizedBox(height: AppSpacing.xs),
        _SensorReadoutCard(side: WheelSide.right),
        SizedBox(height: AppSpacing.xs),
        _SensorReadoutCard(side: WheelSide.center),
      ],
    );
  }
}

class _SensorReadoutCard extends ConsumerWidget {
  const _SensorReadoutCard({required this.side});
  final WheelSide side;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conn = ref.watch(connectionManagerProvider.select((s) => s.bySide[side]!));
    final imu = ref.watch(imuStreamProvider.select((s) => s.bySide[side]!));
    final theme = Theme.of(context);
    final wc = context.wheelColors;
    final role = wc.forWheel(side);

    final isConnected = conn.status == ConnectionStatus.connected;
    final r = imu.latest;

    return Card(
      color: role.container.withAlpha(40),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
        child: Column(
          children: [
            Row(
              children: [
                StatusBadge(
                  label: side.shortLabel,
                  tone: switch (side) {
                    WheelSide.left => BadgeTone.left,
                    WheelSide.right => BadgeTone.right,
                    WheelSide.center => BadgeTone.center,
                  },
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  side.deviceLabel,
                  style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text(
                  isConnected ? 'Connected (${conn.batteryPercent != null ? "${conn.batteryPercent}%" : "Ready"})' : 'Disconnected',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isConnected ? Colors.green : theme.colorScheme.onSurfaceVariant,
                    fontWeight: isConnected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
            if (isConnected && r != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _metricPill('ax', '${r.ax.toStringAsFixed(2)} g'),
                  _metricPill('ay', '${r.ay.toStringAsFixed(2)} g'),
                  _metricPill('az', '${r.az.toStringAsFixed(2)} g'),
                  _metricPill('gx', '${r.gx.toStringAsFixed(1)} °/s'),
                  _metricPill('gy', '${r.gy.toStringAsFixed(1)} °/s'),
                  _metricPill('gz', '${r.gz.toStringAsFixed(1)} °/s'),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _metricPill(String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
