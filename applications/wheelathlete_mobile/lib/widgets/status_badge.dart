import 'package:flutter/material.dart';

import 'package:wheelathlete/theme/theme.dart';

/// Semantic tone for a [StatusBadge]. Maps to design-system color roles.
enum BadgeTone { neutral, info, success, warning, danger, left, right }

/// A compact pill that communicates state at a glance — connection status,
/// sync quality, wheel identity, recording state, etc.
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    this.tone = BadgeTone.neutral,
    this.icon,
    this.dense = false,
  });

  final String label;
  final BadgeTone tone;
  final IconData? icon;

  /// Tighter padding for inline use.
  final bool dense;

  ({Color fg, Color bg}) _colors(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final wc = context.wheelColors;
    return switch (tone) {
      BadgeTone.neutral => (
        fg: scheme.onSurfaceVariant,
        bg: scheme.surfaceContainerHigh,
      ),
      BadgeTone.info => (
        fg: scheme.onPrimaryContainer,
        bg: scheme.primaryContainer,
      ),
      BadgeTone.success => (
        fg: wc.success.onContainer,
        bg: wc.success.container,
      ),
      BadgeTone.warning => (
        fg: wc.warning.onContainer,
        bg: wc.warning.container,
      ),
      BadgeTone.danger => (fg: wc.danger.onContainer, bg: wc.danger.container),
      BadgeTone.left => (fg: wc.left.onContainer, bg: wc.left.container),
      BadgeTone.right => (fg: wc.right.onContainer, bg: wc.right.container),
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = _colors(context);
    final textStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: c.fg,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.2,
    );
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? AppSpacing.xs : AppSpacing.sm,
        vertical: dense ? 2 : AppSpacing.xxs,
      ),
      decoration: BoxDecoration(color: c.bg, borderRadius: AppRadius.brSm),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: dense ? 13 : 15, color: c.fg),
            const SizedBox(width: AppSpacing.xxs),
          ],
          Text(label, style: textStyle),
        ],
      ),
    );
  }
}
