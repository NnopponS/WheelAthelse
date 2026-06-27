import 'package:flutter/material.dart';

import 'package:wheelathlete/theme/theme.dart';

/// A single live IMU readout (one axis of accel or gyro).
///
/// Uses the monospace tabular metric style so the value doesn't jitter
/// horizontally as digits change — critical for reading while the chair moves.
/// Optionally tinted to a wheel identity color.
class LiveMetricTile extends StatelessWidget {
  const LiveMetricTile({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    this.side,
    this.fractionDigits = 2,
  });

  /// Axis label, e.g. "ax", "gy".
  final String label;

  /// Current value.
  final double value;

  /// Unit suffix, e.g. "g", "°/s".
  final String unit;

  /// When set, the value is tinted with that wheel's identity color.
  final WheelSide? side;

  final int fractionDigits;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final valueColor = side == null
        ? scheme.onSurface
        : context.wheelColors.forWheel(side!).solid;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: AppRadius.brMd,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: AppTypography.eyebrow(scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  _formatted,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.metric(color: valueColor, fontSize: 22),
                ),
              ),
              const SizedBox(width: 3),
              Text(
                unit,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String get _formatted {
    final sign = value >= 0 ? '+' : '-';
    return '$sign${value.abs().toStringAsFixed(fractionDigits)}';
  }
}
