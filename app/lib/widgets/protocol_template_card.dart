import 'package:flutter/material.dart';

import 'package:wheelathlete/state/experiment_tracker_providers.dart';
import 'package:wheelathlete/theme/theme.dart';

/// A card on the Experiment tracker dashboard showing one protocol template's
/// progress against its target trial count (Phase 3, §8).
///
/// Renders the template name (title), description (subtitle), a
/// [LinearProgressIndicator] for `sessionCount / targetTrialCount`, an
/// "X / Y trials" label, and the last session date. The leading accent color is
/// green when the target is met ([ExperimentProgress.isComplete]) and amber
/// (warning) while in progress. Tapping the card invokes [onTap], which the
/// dashboard wires up to switch to the Browse tab at the template's topic.
class ProtocolTemplateCard extends StatelessWidget {
  const ProtocolTemplateCard({super.key, required this.progress, this.onTap});

  final ExperimentProgress progress;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final wc = context.wheelColors;
    final accent = progress.isComplete ? wc.success.solid : wc.warning.solid;
    final template = progress.template;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Colored accent strip signaling completion state.
              Container(
                width: 4,
                height: 56,
                margin: const EdgeInsets.only(right: AppSpacing.sm),
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: AppRadius.brSm,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      template.name,
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (template.description != null &&
                        template.description!.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        template.description!,
                        style: theme.textTheme.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                    LinearProgressIndicator(
                      value: progress.progress,
                      minHeight: 8,
                      borderRadius: const BorderRadius.all(
                        Radius.circular(AppRadius.pill),
                      ),
                      backgroundColor: scheme.surfaceContainerHigh,
                      color: accent,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      children: [
                        Text(
                          '${progress.sessionCount} / ${template.targetTrialCount} trials',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: accent,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        if (progress.lastSessionDate != null)
                          Text(
                            _formatDate(progress.lastSessionDate!),
                            style: theme.textTheme.labelSmall,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatDate(DateTime date) {
    final y = date.year.toString();
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
