import 'package:flutter/material.dart';

import 'package:wheelathlete/theme/theme.dart';
import 'package:wheelathlete/widgets/status_badge.dart';

/// BLE connection state for one wheel device.
enum ConnectionStatus {
  disconnected('Disconnected'),
  connecting('Connecting'),
  connected('Connected');

  const ConnectionStatus(this.label);
  final String label;
}

/// Shows the live status of one wheel's BLE link (L or R): connection state,
/// battery, and signal strength. The wheel identity color runs down the left
/// edge as an accent rail so L/R is recognizable at a glance.
class ConnectionCard extends StatelessWidget {
  const ConnectionCard({
    super.key,
    required this.side,
    required this.status,
    this.deviceName,
    this.batteryPercent,
    this.rssi,
    this.onTap,
    this.onSettings,
    this.onDisconnect,
  });

  final WheelSide side;
  final ConnectionStatus status;

  /// Advertised device name (e.g. "WheelAthlete-L"). Falls back to a placeholder.
  final String? deviceName;

  /// 0–100, or null when unknown/disconnected.
  final int? batteryPercent;

  /// BLE RSSI in dBm (negative), or null when unknown.
  final int? rssi;

  final VoidCallback? onTap;

  /// Opens the Board Settings screen for this wheel. Only shown when connected.
  final VoidCallback? onSettings;

  /// Disconnects this wheel. Only shown when connected.
  final VoidCallback? onDisconnect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final role = context.wheelColors.forWheel(side);
    final connected = status == ConnectionStatus.connected;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Wheel-identity accent rail.
            Container(width: 6, color: role.solid),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _WheelGlyph(side: side, role: role),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${side.label} wheel',
                                style: theme.textTheme.titleMedium,
                              ),
                              Text(
                                deviceName ?? 'No device',
                                style: theme.textTheme.bodySmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        _StatusBadge(status: status),
                        if (connected && onSettings != null) ...[
                          const SizedBox(width: AppSpacing.xs),
                          IconButton(
                            tooltip: 'Board settings',
                            iconSize: 20,
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                            onPressed: onSettings,
                            icon: const Icon(Icons.settings_rounded),
                          ),
                        ],
                        if (connected && onDisconnect != null) ...[
                          const SizedBox(width: AppSpacing.xs),
                          IconButton(
                            tooltip: 'Disconnect',
                            iconSize: 20,
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                            onPressed: onDisconnect,
                            icon: const Icon(Icons.link_off_rounded),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        _Telemetry(
                          icon: _batteryIcon(batteryPercent),
                          value: batteryPercent == null
                              ? '--'
                              : '$batteryPercent%',
                          color: _batteryColor(context, batteryPercent),
                          enabled: connected && batteryPercent != null,
                        ),
                        const SizedBox(width: AppSpacing.lg),
                        _Telemetry(
                          icon: Icons.wifi_tethering_rounded,
                          value: rssi == null ? '--' : '$rssi dBm',
                          color: scheme.onSurfaceVariant,
                          enabled: connected && rssi != null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }

  static IconData _batteryIcon(int? pct) {
    if (pct == null) return Icons.battery_unknown_rounded;
    if (pct >= 90) return Icons.battery_full_rounded;
    if (pct >= 60) return Icons.battery_5_bar_rounded;
    if (pct >= 35) return Icons.battery_3_bar_rounded;
    if (pct >= 15) return Icons.battery_2_bar_rounded;
    return Icons.battery_alert_rounded;
  }

  static Color _batteryColor(BuildContext context, int? pct) {
    final wc = context.wheelColors;
    if (pct == null) return Theme.of(context).colorScheme.onSurfaceVariant;
    if (pct <= 15) return wc.danger.solid;
    if (pct <= 35) return wc.warning.solid;
    return wc.success.solid;
  }
}

class _WheelGlyph extends StatelessWidget {
  const _WheelGlyph({required this.side, required this.role});

  final WheelSide side;
  final ColorRole role;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: role.container,
        borderRadius: AppRadius.brMd,
      ),
      child: Text(
        side.shortLabel,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: role.onContainer,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final ConnectionStatus status;

  @override
  Widget build(BuildContext context) {
    final (tone, icon) = switch (status) {
      ConnectionStatus.connected => (BadgeTone.success, Icons.check_circle_rounded),
      ConnectionStatus.connecting => (BadgeTone.warning, Icons.sync_rounded),
      ConnectionStatus.disconnected => (BadgeTone.neutral, Icons.cloud_off_rounded),
    };
    return StatusBadge(label: status.label, tone: tone, icon: icon);
  }
}

class _Telemetry extends StatelessWidget {
  const _Telemetry({
    required this.icon,
    required this.value,
    required this.color,
    required this.enabled,
  });

  final IconData icon;
  final String value;
  final Color color;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effective = enabled ? color : theme.colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: effective),
        const SizedBox(width: AppSpacing.xxs),
        Text(
          value,
          style: theme.textTheme.labelMedium?.copyWith(color: effective),
        ),
      ],
    );
  }
}
