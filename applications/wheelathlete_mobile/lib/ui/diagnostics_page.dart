import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wheelathlete/state/ble_providers.dart';
import 'package:wheelathlete/state/diagnostics_providers.dart';
import 'package:wheelathlete/theme/theme.dart';
import 'package:wheelathlete/update/app_version.dart';
import 'package:wheelathlete/widgets/widgets.dart';

/// Diagnostics screen: displays a 4-column matrix of sensor, transport, and
/// clock metrics: [Metric, Left (L), Right (R), Center (C)].
///
/// Features:
/// - Realtime matrix table with alternating row colors and role badges.
/// - Fast refresh action.
/// - JSON diagnostics report export/share via share_plus.
/// - Software & firmware version summary card.
class DiagnosticsPage extends ConsumerWidget {
  const DiagnosticsPage({super.key});

  Future<void> _exportDiagnostics(BuildContext context, WidgetRef ref) async {
    final jsonStr = generateDiagnosticsJson(ref);
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: jsonStr,
          subject: 'wheelathlete-diagnostics.json',
        ),
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Diagnostics report exported.')),
        );
      }
    } on Object catch (_) {
      // Fallback: Copy to clipboard if share modal is unavailable
      await Clipboard.setData(ClipboardData(text: jsonStr));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Diagnostics JSON copied to clipboard.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(diagnosticsMetricsProvider);
    final connState = ref.watch(connectionManagerProvider);
    final theme = Theme.of(context);
    final wc = context.wheelColors;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostics'),
        actions: [
          IconButton(
            tooltip: 'Export report',
            icon: const Icon(Icons.share_rounded),
            onPressed: () => _exportDiagnostics(context, ref),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          // Toolbar actions
          Row(
            children: [
              FilledButton.icon(
                onPressed: () => _exportDiagnostics(context, ref),
                icon: const Icon(Icons.ios_share_rounded),
                label: const Text('Export report'),
              ),
              const SizedBox(width: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: () {
                  ref.invalidate(diagnosticsMetricsProvider);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Diagnostics refreshed.'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Refresh'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // 4-column diagnostic matrix card
          Card(
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(
                  theme.colorScheme.surfaceContainerHighest.withAlpha(120),
                ),
                columnSpacing: AppSpacing.lg,
                horizontalMargin: AppSpacing.md,
                columns: [
                  DataColumn(
                    label: Text(
                      'Metric',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const StatusBadge(
                          label: 'L',
                          tone: BadgeTone.left,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Left',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: wc.left.solid,
                          ),
                        ),
                      ],
                    ),
                  ),
                  DataColumn(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const StatusBadge(
                          label: 'R',
                          tone: BadgeTone.right,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Right',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: wc.right.solid,
                          ),
                        ),
                      ],
                    ),
                  ),
                  DataColumn(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const StatusBadge(
                          label: 'C',
                          tone: BadgeTone.center,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Center',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: wc.center.solid,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                rows: [
                  for (var i = 0; i < rows.length; i++)
                    DataRow(
                      color: WidgetStateProperty.all(
                        i.isEven
                            ? Colors.transparent
                            : theme.colorScheme.surfaceContainerLowest.withAlpha(50),
                      ),
                      cells: [
                        DataCell(
                          Text(
                            rows[i].metric,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        DataCell(
                          Text(
                            rows[i].left,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                        DataCell(
                          Text(
                            rows[i].right,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                        DataCell(
                          Text(
                            rows[i].center,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: AppSpacing.md),

          // Versions and Host Environment Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.info_outline_rounded),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        'System Information',
                        style: theme.textTheme.titleSmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'App Version: WheelAthlete $wheelAthleteAppVersion (build $wheelAthleteAppBuild)',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    'Bluetooth subsystem: flutter_blue_plus 2.3.9',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    'Connected sensors: ${connState.bySide.values.where((c) => c.status == ConnectionStatus.connected).length} of 3',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
