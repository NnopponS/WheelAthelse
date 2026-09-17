import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wheelathlete/model/analysis_contract.dart';
import 'package:wheelathlete/model/three_imu_trajectory_model.dart';
import 'package:wheelathlete/model/trajectory_model.dart';
import 'package:wheelathlete/records/session_model.dart';
import 'package:wheelathlete/state/ble_providers.dart';
import 'package:wheelathlete/state/model_management_providers.dart';
import 'package:wheelathlete/theme/theme.dart';
import 'package:wheelathlete/widgets/trajectory_chart.dart';

/// Provider returning all finalized sessions from storage for the model page.
final _allSessionsForModelProvider = FutureProvider.autoDispose<List<SessionMeta>>((ref) async {
  final storage = ref.watch(storageRepositoryProvider);
  return storage.listAllSessions();
});

/// Dedicated Model Page: runs on-device BiWheel3D trajectory inference and
/// kinematic analysis for finalized recordings.
///
/// Parity with Python PC GUI ModelPage:
/// - Model selection (Kinematic recipe vs BiWheel3D M4 ONNX)
/// - Model specifications card (capabilities, inputs, version)
/// - Session selector dropdown
/// - "Generate Trajectory" action
/// - Equal-aspect 2D trajectory view with start (green) and finish (red) markers
/// - Kinematic summary metrics: Distance, Endpoint, Duration, Peak/Mean Speed, Net Yaw, Max Yaw Rate
/// - Kinematic timeline charts (Speed vs Time, Yaw Rate vs Time)
class ModelPage extends ConsumerWidget {
  const ModelPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final availableModels = ref.watch(availableModelsProvider);
    final selectedKey = ref.watch(selectedModelKeyProvider);
    final activeSpec = ref.watch(activeModelSpecProvider);
    final selectedSessionId = ref.watch(selectedModelSessionIdProvider);
    final inferenceState = ref.watch(modelInferenceProvider);
    final inferenceNotifier = ref.read(modelInferenceProvider.notifier);
    final sessionsAsync = ref.watch(_allSessionsForModelProvider);

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Model & Trajectory'),
        actions: [
          if (inferenceState.isRunning)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          // 1. Model & Session Selector Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.psychology_rounded),
                      const SizedBox(width: AppSpacing.xs),
                      Text('Model Selection', style: theme.textTheme.titleSmall),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  // Model dropdown
                  DropdownButtonFormField<String>(
                    initialValue: selectedKey,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Select Trajectory Model',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xs,
                      ),
                    ),
                    items: [
                      for (final m in availableModels)
                        DropdownMenuItem(
                          value: m.key,
                          child: Text(
                            m.label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (key) {
                      if (key != null) {
                        ref.read(selectedModelKeyProvider.notifier).set(key);
                      }
                    },
                  ),
                  const SizedBox(height: AppSpacing.sm),

                  // Session dropdown
                  sessionsAsync.when(
                    data: (sessions) {
                      if (sessions.isEmpty) {
                        return const Text('No recorded sessions found.');
                      }
                      final effectiveSessionId = selectedSessionId != null &&
                              sessions.any((s) => s.sessionId == selectedSessionId)
                          ? selectedSessionId
                          : sessions.first.sessionId;

                      return DropdownButtonFormField<String>(
                        initialValue: effectiveSessionId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Select Session',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: AppSpacing.xs,
                          ),
                        ),
                        items: [
                          for (final s in sessions)
                            DropdownMenuItem(
                              value: s.sessionId,
                              child: Text(
                                '${s.recordedSides.contains('C') ? '[3-IMU]' : '[2-IMU]'} ${s.topic} / Trial ${s.trialNumber} (${s.sessionId})',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (sessionId) {
                          if (sessionId != null) {
                            ref.read(selectedModelSessionIdProvider.notifier).set(sessionId);
                            final s = sessions.where((item) => item.sessionId == sessionId).firstOrNull;
                            if (s != null && s.recordedSides.contains('C')) {
                              ref.read(selectedModelKeyProvider.notifier).set(threeImuV4ModelKey);
                            }
                          }
                        },
                      );
                    },
                    loading: () => const LinearProgressIndicator(),
                    error: (err, _) => Text('Error loading sessions: $err'),
                  ),

                  const SizedBox(height: AppSpacing.md),

                  // Generate Button
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: inferenceState.isRunning
                          ? null
                          : () {
                              final sessions = sessionsAsync.value ?? [];
                              if (sessions.isEmpty) return;
                              final sessionId = selectedSessionId ?? sessions.first.sessionId;
                              inferenceNotifier.runOnSessionId(sessionId);
                            },
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text(
                        inferenceState.isRunning
                            ? 'Generating Trajectory…'
                            : 'Generate 2D Trajectory',
                      ),
                    ),
                  ),

                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    inferenceState.statusMessage,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: inferenceState.error != null
                          ? scheme.error
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: AppSpacing.md),

          // 2. Model Specs Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.description_outlined),
                      const SizedBox(width: AppSpacing.xs),
                      Text('Model Specification', style: theme.textTheme.titleSmall),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    activeSpec.description,
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xxs,
                    children: [
                      Chip(
                        label: Text('Kind: ${activeSpec.kind.toUpperCase()}'),
                        visualDensity: VisualDensity.compact,
                      ),
                      Chip(
                        label: Text('Version: ${activeSpec.modelVersion}'),
                        visualDensity: VisualDensity.compact,
                      ),
                      Chip(
                        label: Text('Inputs: ${activeSpec.requiredSensorRoles.join(' / ')}'),
                        visualDensity: VisualDensity.compact,
                      ),
                      Chip(
                        label: Text('Outputs: ${activeSpec.outputCapabilities.join(', ')}'),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: AppSpacing.md),

          // 3. Trajectory & Analysis Results (if generated)
          if (inferenceState.result != null) ...[
            _TrajectoryDisplayCard(result: inferenceState.result!),
            const SizedBox(height: AppSpacing.md),
            _KinematicMetricsCard(result: inferenceState.result!),
            const SizedBox(height: AppSpacing.md),
            if (inferenceState.result!.analysis != null) ...[
              _KinematicTimelineCard(analysis: inferenceState.result!.analysis!),
              const SizedBox(height: AppSpacing.md),
            ],
          ],
        ],
      ),
    );
  }
}

class _TrajectoryDisplayCard extends StatelessWidget {
  const _TrajectoryDisplayCard({required this.result});

  final TrajectoryResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wc = context.wheelColors;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.alt_route_rounded),
                const SizedBox(width: AppSpacing.xs),
                Text('2D Planar Trajectory', style: theme.textTheme.titleSmall),
                const Spacer(),
                if (result.modelKey == threeImuV4ModelKey || result.modelLabel.contains('3IMU')) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F766E).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFF0F766E)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.verified_outlined, size: 12, color: Color(0xFF0F766E)),
                        SizedBox(width: 3),
                        Text(
                          '3-IMU Calibrated',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF0F766E),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                ],
                Text(
                  '${result.points.length} points',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: wc.left.solid, shape: BoxShape.circle)),
                const SizedBox(width: 4),
                Text('Start (0,0)', style: theme.textTheme.labelSmall),
                const SizedBox(width: AppSpacing.md),
                Container(width: 8, height: 8, decoration: BoxDecoration(color: wc.right.solid, shape: BoxShape.circle)),
                const SizedBox(width: 4),
                Text('Finish', style: theme.textTheme.labelSmall),
                const Spacer(),
                const Text('Equal X/Y Scale (metres)', style: TextStyle(fontSize: 10, color: Colors.grey)),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            TrajectoryChart(points: result.points),
          ],
        ),
      ),
    );
  }
}

class _KinematicMetricsCard extends StatelessWidget {
  const _KinematicMetricsCard({required this.result});

  final TrajectoryResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final analysis = result.analysis;
    final summary = analysis?.summary ?? {};

    final distanceM = (summary['distance_m'] as num?)?.toDouble() ?? result.pathLengthM;
    final endpointM = result.endpointM;
    final durationS = (summary['duration_s'] as num?)?.toDouble() ?? 0.0;
    final peakSpeed = (summary['peak_speed_mps'] as num?)?.toDouble();
    final meanSpeed = (summary['mean_speed_mps'] as num?)?.toDouble();
    final netYawDeg = (summary['net_yaw_deg'] as num?)?.toDouble();
    final maxYawRate = (summary['max_yaw_rate_degps'] as num?)?.toDouble();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.analytics_outlined),
                const SizedBox(width: AppSpacing.xs),
                Text('Kinematic Summary', style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.sm,
              children: [
                _MetricItem(label: 'Distance', value: '${distanceM.toStringAsFixed(2)} m'),
                _MetricItem(label: 'Endpoint', value: '${endpointM.toStringAsFixed(2)} m'),
                if (durationS > 0)
                  _MetricItem(label: 'Duration', value: '${durationS.toStringAsFixed(1)} s'),
                if (meanSpeed != null)
                  _MetricItem(label: 'Mean Speed', value: '${meanSpeed.toStringAsFixed(2)} m/s'),
                if (peakSpeed != null)
                  _MetricItem(label: 'Peak Speed', value: '${peakSpeed.toStringAsFixed(2)} m/s'),
                if (netYawDeg != null)
                  _MetricItem(label: 'Net Yaw', value: '${netYawDeg.toStringAsFixed(1)}°'),
                if (maxYawRate != null)
                  _MetricItem(label: 'Max Yaw Rate', value: '${maxYawRate.toStringAsFixed(1)}°/s'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricItem extends StatelessWidget {
  const _MetricItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 100,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _KinematicTimelineCard extends StatelessWidget {
  const _KinematicTimelineCard({required this.analysis});

  final KinematicAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final samples = analysis.samples;

    final speedSpots = <FlSpot>[];
    final yawRateSpots = <FlSpot>[];

    for (final s in samples) {
      final t = s.timeS;
      final speed = s['signed_speed_mps'] ?? s['speed_mps'];
      if (speed != null) speedSpots.add(FlSpot(t, speed));
      final yr = s['yaw_rate_radps'];
      if (yr != null) yawRateSpots.add(FlSpot(t, yr * 180.0 / math.pi));
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.timeline_rounded),
                const SizedBox(width: AppSpacing.xs),
                Text('Kinematic Timeline', style: theme.textTheme.titleSmall),
              ],
            ),
            if (speedSpots.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Speed (m/s) vs Time (s)',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              SizedBox(
                height: 120,
                child: LineChart(
                  duration: Duration.zero,
                  LineChartData(
                    lineBarsData: [
                      LineChartBarData(
                        spots: speedSpots,
                        color: scheme.primary,
                        barWidth: 2,
                        dotData: const FlDotData(show: false),
                      ),
                    ],
                    titlesData: const FlTitlesData(show: false),
                    gridData: const FlGridData(show: true, drawVerticalLine: false),
                    borderData: FlBorderData(show: false),
                    clipData: const FlClipData.all(),
                  ),
                ),
              ),
            ],
            if (yawRateSpots.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                'Yaw Rate (°/s) vs Time (s)',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: scheme.secondary,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              SizedBox(
                height: 120,
                child: LineChart(
                  duration: Duration.zero,
                  LineChartData(
                    lineBarsData: [
                      LineChartBarData(
                        spots: yawRateSpots,
                        color: scheme.secondary,
                        barWidth: 2,
                        dotData: const FlDotData(show: false),
                      ),
                    ],
                    titlesData: const FlTitlesData(show: false),
                    gridData: const FlGridData(show: true, drawVerticalLine: false),
                    borderData: FlBorderData(show: false),
                    clipData: const FlClipData.all(),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
