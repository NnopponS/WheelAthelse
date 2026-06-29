import 'package:flutter/material.dart';

import 'package:wheelathlete/theme/theme.dart';
import 'package:wheelathlete/widgets/status_badge.dart';

/// A row in the browse screen (topic → trial → session). Surfaces the most
/// useful at-a-glance metadata: when it was recorded, how long, sample count,
/// and sync quality, plus a marker count badge.
class SessionListItem extends StatelessWidget {
  const SessionListItem({
    super.key,
    required this.title,
    required this.subtitle,
    this.duration,
    this.sampleCount,
    this.markerCount = 0,
    this.syncQuality,
    this.onTap,
    this.onShare,
    this.onSave,
    this.onEdit,
  });

  final String title;

  /// e.g. "trial_03 · 2026-06-28 14:21".
  final String subtitle;

  final Duration? duration;
  final int? sampleCount;
  final int markerCount;

  /// Optional sync-quality label (e.g. "±0.8 ms"). Tone is chosen by the caller
  /// implicitly via [syncQuality]; here we just render it as info.
  final String? syncQuality;

  final VoidCallback? onTap;
  final VoidCallback? onShare;

  /// Optional save-to-device callback. When set, a save icon button is shown.
  final VoidCallback? onSave;

  /// Optional edit callback. When set, an overflow menu is shown that lets the
  /// user edit the session's notes / video filename.
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHigh,
                      borderRadius: AppRadius.brMd,
                    ),
                    child: Icon(
                      Icons.show_chart_rounded,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          subtitle,
                          style: theme.textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (onShare != null)
                    IconButton(
                      onPressed: onShare,
                      icon: const Icon(Icons.ios_share_rounded),
                      tooltip: 'Share',
                    ),
                  if (onSave != null)
                    IconButton(
                      onPressed: onSave,
                      icon: const Icon(Icons.save_alt_rounded),
                      tooltip: 'Save to device',
                    ),
                  if (onEdit != null)
                    PopupMenuButton<String>(
                      tooltip: 'More',
                      icon: const Icon(Icons.more_vert_rounded),
                      onSelected: (value) {
                        if (value == 'edit') onEdit?.call();
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: ListTile(
                            leading: Icon(Icons.edit_note_rounded),
                            title: Text('Edit notes / video'),
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  if (duration != null)
                    StatusBadge(
                      label: _fmtDuration(duration!),
                      icon: Icons.timer_outlined,
                      dense: true,
                    ),
                  if (sampleCount != null)
                    StatusBadge(
                      label: '${_fmtCount(sampleCount!)} samples',
                      icon: Icons.scatter_plot_rounded,
                      dense: true,
                    ),
                  if (markerCount > 0)
                    StatusBadge(
                      label: '$markerCount marks',
                      icon: Icons.flag_rounded,
                      tone: BadgeTone.info,
                      dense: true,
                    ),
                  if (syncQuality != null)
                    StatusBadge(
                      label: 'sync $syncQuality',
                      icon: Icons.sync_alt_rounded,
                      tone: BadgeTone.success,
                      dense: true,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _fmtDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return m > 0 ? '${m}m ${s}s' : '${s}s';
  }

  static String _fmtCount(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }
}
