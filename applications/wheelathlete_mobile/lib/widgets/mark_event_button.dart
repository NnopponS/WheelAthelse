import 'package:flutter/material.dart';

import 'package:wheelathlete/theme/theme.dart';

/// A large circular "Mark Event" control used during recording to drop a sync
/// marker (for aligning IMU data with the camera). Big and centered so it can
/// be tapped reliably without looking. Shows a running marker count.
class MarkEventButton extends StatelessWidget {
  const MarkEventButton({
    super.key,
    required this.onPressed,
    this.markerCount = 0,
    this.enabled = true,
  });

  final VoidCallback? onPressed;
  final int markerCount;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final active = enabled && onPressed != null;
    final accent = active ? scheme.primary : scheme.onSurfaceVariant;

    return Semantics(
      button: true,
      enabled: active,
      label: 'Mark event, $markerCount so far',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: AppSizing.markButton,
            height: AppSizing.markButton,
            child: Material(
              color: active
                  ? scheme.primaryContainer
                  : scheme.surfaceContainerHigh,
              shape: CircleBorder(side: BorderSide(color: accent, width: 2)),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: active ? onPressed : null,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.flag_rounded, size: 30, color: accent),
                    Text('MARK', style: AppTypography.eyebrow(accent)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            markerCount == 1 ? '1 marker' : '$markerCount markers',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
