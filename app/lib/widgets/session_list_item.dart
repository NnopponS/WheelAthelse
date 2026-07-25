import 'package:flutter/material.dart';

import 'package:wheelathlete/records/quality_badge.dart';
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
    this.qualityLevel,
    this.tags = const [],
    this.onTap,
    this.onShare,
    this.onSave,
    this.onEdit,
    this.onEditTags,
    this.onDelete,
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

  /// Optional [SyncQuality] level used to pick the badge color tone. When
  /// provided, the sync badge is colored green (good), amber (fair), red
  /// (poor), or grey (unknown). When `null` but [syncQuality] is set, the
  /// badge falls back to [BadgeTone.neutral].
  final SyncQuality? qualityLevel;

  /// Free-form tags/labels for this session. Shown as small chips below the
  /// subtitle. Defaults to an empty list (no chips rendered).
  final List<String> tags;

  final VoidCallback? onTap;
  final VoidCallback? onShare;

  /// Optional save-to-device callback. When set, a save icon button is shown.
  final VoidCallback? onSave;

  /// Optional edit callback. When set, an overflow menu is shown that lets the
  /// user edit the session's notes / video filename.
  final VoidCallback? onEdit;

  /// Optional edit-tags callback. When set, the overflow menu gains an
  /// "Edit tags" entry that opens the tag editor dialog.
  final VoidCallback? onEditTags;

  /// Optional delete callback. When set, a delete icon button is shown.
  final VoidCallback? onDelete;

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
                        if (tags.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.xxs),
                          Wrap(
                            spacing: AppSpacing.xxs,
                            runSpacing: AppSpacing.xxs,
                            children: [
                              for (final tag in tags)
                                Chip(
                                  label: Text(tag),
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  labelPadding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.xs,
                                  ),
                                  backgroundColor: scheme.secondaryContainer,
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (onDelete != null)
                    IconButton(
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline_rounded),
                      tooltip: 'Delete',
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
                  if (onEdit != null || onEditTags != null)
                    PopupMenuButton<String>(
                      tooltip: 'More',
                      icon: const Icon(Icons.more_vert_rounded),
                      onSelected: (value) {
                        if (value == 'edit') onEdit?.call();
                        if (value == 'edit_tags') onEditTags?.call();
                      },
                      itemBuilder: (context) => [
                        if (onEdit != null)
                          const PopupMenuItem(
                            value: 'edit',
                            child: ListTile(
                              leading: Icon(Icons.edit_note_rounded),
                              title: Text('Edit notes / video'),
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                            ),
                          ),
                        if (onEditTags != null)
                          const PopupMenuItem(
                            value: 'edit_tags',
                            child: ListTile(
                              leading: Icon(Icons.sell_outlined),
                              title: Text('Edit tags'),
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
                      tone: _syncTone(qualityLevel),
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

  /// Maps a [SyncQuality] level to a [BadgeTone] for the sync badge. Falls
  /// back to [BadgeTone.neutral] when [qualityLevel] is `null` (caller did not
  /// classify the session).
  static BadgeTone _syncTone(SyncQuality? level) {
    return switch (level) {
      SyncQuality.good => BadgeTone.success,
      SyncQuality.fair => BadgeTone.warning,
      SyncQuality.poor => BadgeTone.danger,
      SyncQuality.unknown => BadgeTone.neutral,
      null => BadgeTone.neutral,
    };
  }
}
