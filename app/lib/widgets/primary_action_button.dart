import 'package:flutter/material.dart';

import 'package:wheelsense/theme/theme.dart';

/// Visual intent for [PrimaryActionButton].
enum ActionIntent { start, stop, neutral }

/// A large, full-width primary action — the main "Start recording" /
/// "Stop recording" control. Sized for easy thumb hits while in the field,
/// with a clear color shift between start (go) and stop (danger) states and a
/// built-in busy state.
class PrimaryActionButton extends StatelessWidget {
  const PrimaryActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.intent = ActionIntent.neutral,
    this.busy = false,
  });

  final String label;

  /// Null disables the button.
  final VoidCallback? onPressed;
  final IconData? icon;
  final ActionIntent intent;

  /// Shows a spinner and blocks taps (e.g. during synchronized-start countdown
  /// handshake).
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wc = context.wheelColors;
    final (bg, fg) = switch (intent) {
      ActionIntent.start => (wc.success.solid, wc.success.on),
      ActionIntent.stop => (wc.danger.solid, wc.danger.on),
      ActionIntent.neutral => (
          theme.colorScheme.primary,
          theme.colorScheme.onPrimary,
        ),
    };

    return SizedBox(
      width: double.infinity,
      height: AppSizing.primaryActionHeight,
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          disabledBackgroundColor: bg.withValues(alpha: 0.4),
          disabledForegroundColor: fg.withValues(alpha: 0.7),
          textStyle: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.brLg),
        ),
        child: busy
            ? SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(strokeWidth: 3, color: fg),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 26),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
