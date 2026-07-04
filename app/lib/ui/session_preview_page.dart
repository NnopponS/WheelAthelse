import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wheelathlete/ble/imu_packet.dart';
import 'package:wheelathlete/export/export_actions.dart';
import 'package:wheelathlete/export/export_providers.dart';
import 'package:wheelathlete/records/quality_badge.dart';
import 'package:wheelathlete/records/session_model.dart';
import 'package:wheelathlete/records/session_stats.dart';
import 'package:wheelathlete/state/preview_providers.dart';
import 'package:wheelathlete/theme/theme.dart';
import 'package:wheelathlete/widgets/imu_chart.dart';
import 'package:wheelathlete/widgets/status_badge.dart';

/// Session preview/playback page.
///
/// Shows summary stats, a scrub slider, a wheel selector, and accel + gyro
/// charts for the selected wheel(s). Lazy-loads sample chunks around the scrub
/// position via [PreviewController] (debounced).
///
/// Pass a [DiskPreviewSource] to load a saved session from storage (Browse
/// tap), or an [InMemoryPreviewSource] to preview a just-stopped recording
/// without going through disk.
class SessionPreviewPage extends ConsumerWidget {
  const SessionPreviewPage({super.key, required this.source, this.title});

  /// Identifies the session to preview.
  final PreviewSource source;

  /// Optional AppBar title override. Defaults to the session id.
  final String? title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(previewControllerProvider(source));
    final exportState = ref.watch(exportProvider);
    final theme = Theme.of(context);
    final wc = context.wheelColors;
    final canExport = !state.isLoading && state.error == null;

    return Scaffold(
      appBar: AppBar(
        title: Text(title ?? state.meta.sessionId),
        actions: [
          if (state.isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else ...[
            IconButton(
              onPressed: (exportState.isExporting || !canExport)
                  ? null
                  : () => _share(context, ref, state.meta),
              icon: const Icon(Icons.ios_share_rounded),
              tooltip: 'Share',
            ),
            PopupMenuButton<String>(
              tooltip: 'More',
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (value) {
                if (value == 'save') {
                  _saveToDevice(context, ref, state.meta);
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'save',
                  enabled: !exportState.isExporting && canExport,
                  child: const ListTile(
                    leading: Icon(Icons.save_alt_rounded),
                    title: Text('Save to device'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.error != null
              ? _ErrorView(message: state.error!)
              : _PreviewBody(source: source, state: state, theme: theme, wc: wc),
    );
  }

  /// Shares the session CSV via share_plus (Phase 4, subtask #35). Uses the
  /// shared [exportActionsProvider] — same path as Browse share. Works for
  /// both disk and in-memory sources because the session is already saved to
  /// disk by the time the preview opens.
  Future<void> _share(
    BuildContext context,
    WidgetRef ref,
    SessionMeta meta,
  ) async {
    final actions = ref.read(exportActionsProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await actions.share(
        level: ExportLevel.session,
        topic: meta.topic,
        trialNumber: meta.trialNumber,
        sessionId: meta.sessionId,
      );
    } on Object catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Share failed: $e')));
    }
  }

  /// Saves the session CSV to a user-picked directory (Phase 4, subtask #35).
  Future<void> _saveToDevice(
    BuildContext context,
    WidgetRef ref,
    SessionMeta meta,
  ) async {
    final actions = ref.read(exportActionsProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final written = await actions.saveToDevice(
        level: ExportLevel.session,
        topic: meta.topic,
        trialNumber: meta.trialNumber,
        sessionId: meta.sessionId,
        pickDirectory: pickDirectory,
        writeFile: writeCsvFile,
      );
      if (!context.mounted) return;
      if (written.isEmpty) return; // user cancelled
      messenger.showSnackBar(
        SnackBar(content: Text('Saved ${written.length} file(s) to device')),
      );
    } on Object catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Save failed: $e')));
    }
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded,
                size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: AppSpacing.md),
            Text('Could not load session',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

class _PreviewBody extends ConsumerWidget {
  const _PreviewBody({
    required this.source,
    required this.state,
    required this.theme,
    required this.wc,
  });

  final PreviewSource source;
  final PreviewState state;
  final ThemeData theme;
  final WheelAthleteColors wc;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        _SummaryCard(state: state, theme: theme, wc: wc),
        const SizedBox(height: AppSpacing.md),
        _ScrubSlider(source: source, state: state),
        const SizedBox(height: AppSpacing.sm),
        _WheelSelector(source: source, state: state),
        const SizedBox(height: AppSpacing.md),
        _ChartSection(
          state: state,
          wc: wc,
          isAccel: true,
        ),
        const SizedBox(height: AppSpacing.md),
        _ChartSection(
          state: state,
          wc: wc,
          isAccel: false,
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.state,
    required this.theme,
    required this.wc,
  });

  final PreviewState state;
  final ThemeData theme;
  final WheelAthleteColors wc;

  @override
  Widget build(BuildContext context) {
    final stats = state.stats;
    final meta = state.meta;
    final quality = QualityBadge.fromMeta(meta);
    final qualityLabel = switch (quality) {
      SyncQuality.good => 'Good',
      SyncQuality.fair => 'Fair',
      SyncQuality.poor => 'Poor',
      SyncQuality.unknown => '—',
    };
    final durationStr = _fmtDuration(Duration(milliseconds: meta.durationMs));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Summary', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                StatusBadge(
                  label: durationStr,
                  icon: Icons.timer_outlined,
                  dense: true,
                ),
                StatusBadge(
                  label: '${_fmtCount(meta.sampleCount)} samples',
                  icon: Icons.scatter_plot_rounded,
                  dense: true,
                ),
                if (meta.markerCount > 0)
                  StatusBadge(
                    label: '${meta.markerCount} marks',
                    icon: Icons.flag_rounded,
                    tone: BadgeTone.info,
                    dense: true,
                  ),
                StatusBadge(
                  label: 'sync $qualityLabel',
                  icon: Icons.sync_alt_rounded,
                  tone: _qualityTone(quality),
                  dense: true,
                ),
              ],
            ),
            if (stats != null) ...[
              const SizedBox(height: AppSpacing.sm),
              _StatGrid(stats: stats, theme: theme),
            ],
          ],
        ),
      ),
    );
  }

  static BadgeTone _qualityTone(SyncQuality q) {
    return switch (q) {
      SyncQuality.good => BadgeTone.success,
      SyncQuality.fair => BadgeTone.warning,
      SyncQuality.poor => BadgeTone.danger,
      SyncQuality.unknown => BadgeTone.neutral,
    };
  }
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.stats, required this.theme});
  final SessionStats stats;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 3.2,
      mainAxisSpacing: AppSpacing.xs,
      crossAxisSpacing: AppSpacing.xs,
      children: [
        _statTile('Mean accel', '${stats.meanAccelMagnitude.toStringAsFixed(2)} g'),
        _statTile('Peak accel', '${stats.peakAccelMagnitude.toStringAsFixed(2)} g'),
        _statTile('Mean gyro', '${stats.meanGyroMagnitude.toStringAsFixed(1)} dps'),
        _statTile('Peak gyro', '${stats.peakGyroMagnitude.toStringAsFixed(1)} dps'),
      ],
    );
  }

  Widget _statTile(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: AppRadius.brSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: theme.textTheme.labelSmall),
          Text(value, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _ScrubSlider extends ConsumerWidget {
  const _ScrubSlider({required this.source, required this.state});
  final PreviewSource source;
  final PreviewState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final max = state.meta.durationMs.toDouble();
    final value = state.scrubPositionMs.toDouble().clamp(0.0, max);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Scrub',
                style: Theme.of(context).textTheme.labelMedium),
            Text(
              _fmtDuration(Duration(milliseconds: state.scrubPositionMs)),
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ],
        ),
        Slider(
          min: 0,
          max: max <= 0 ? 1.0 : max,
          value: value.toDouble(),
          onChanged: max <= 0
              ? null
              : (v) => ref
                  .read(previewControllerProvider(source).notifier)
                  .setScrub(v.round()),
        ),
      ],
    );
  }
}

class _WheelSelector extends ConsumerWidget {
  const _WheelSelector({required this.source, required this.state});
  final PreviewSource source;
  final PreviewState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Wrap(
      spacing: AppSpacing.xs,
      children: [
        for (final selection in PreviewWheelSelection.values)
          ChoiceChip(
            label: Text(_label(selection)),
            selected: state.selectedWheel == selection,
            onSelected: (_) => ref
                .read(previewControllerProvider(source).notifier)
                .setWheel(selection),
          ),
      ],
    );
  }

  static String _label(PreviewWheelSelection s) {
    return switch (s) {
      PreviewWheelSelection.both => 'Both',
      PreviewWheelSelection.left => 'Left',
      PreviewWheelSelection.right => 'Right',
    };
  }
}

class _ChartSection extends StatelessWidget {
  const _ChartSection({
    required this.state,
    required this.wc,
    required this.isAccel,
  });

  final PreviewState state;
  final WheelAthleteColors wc;
  final bool isAccel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = isAccel ? 'Accelerometer (g)' : 'Gyroscope (dps)';
    final axisColors = isAccel
        ? [wc.left.solid, wc.right.solid, theme.colorScheme.tertiary]
        : [wc.left.solid, wc.right.solid, theme.colorScheme.tertiary];

    final selection = state.selectedWheel;
    final chunk = state.currentChunk;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.xs),
            if (chunk.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Center(child: Text('No data in this window')),
              )
            else if (selection == PreviewWheelSelection.both)
              Column(
                children: [
                  _WheelChart(
                    readings: toReadings(
                        filterByWheel(chunk, PreviewWheelSelection.left)),
                    isAccel: isAccel,
                    axisColors: axisColors,
                    label: 'L',
                    color: wc.left.solid,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  _WheelChart(
                    readings: toReadings(
                        filterByWheel(chunk, PreviewWheelSelection.right)),
                    isAccel: isAccel,
                    axisColors: axisColors,
                    label: 'R',
                    color: wc.right.solid,
                  ),
                ],
              )
            else
              _WheelChart(
                readings: toReadings(filterByWheel(chunk, selection)),
                isAccel: isAccel,
                axisColors: axisColors,
                label: selection == PreviewWheelSelection.left ? 'L' : 'R',
                color: wc.forWheel(
                        selection == PreviewWheelSelection.left
                            ? WheelSide.left
                            : WheelSide.right)
                    .solid,
              ),
          ],
        ),
      ),
    );
  }
}

class _WheelChart extends StatelessWidget {
  const _WheelChart({
    required this.readings,
    required this.isAccel,
    required this.axisColors,
    required this.label,
    required this.color,
  });

  final List<ImuReading> readings;
  final bool isAccel;
  final List<Color> axisColors;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 24,
          height: 120,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: AppRadius.brSm,
          ),
          child: Text(label,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w700, fontSize: 12)),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: ImuChart(
            readings: readings,
            isAccel: isAccel,
            axisColors: axisColors,
            height: 120,
          ),
        ),
      ],
    );
  }
}

String _fmtDuration(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  final ms = d.inMilliseconds % 1000;
  if (m > 0) return '${m}m $s.${(ms ~/ 100)}s';
  return '$s.${(ms ~/ 100)}s';
}

String _fmtCount(int n) {
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
  return '$n';
}
