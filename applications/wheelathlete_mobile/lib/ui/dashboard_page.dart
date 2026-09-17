import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wheelathlete/state/ble_providers.dart';
import 'package:wheelathlete/state/dashboard_providers.dart';
import 'package:wheelathlete/state/home_providers.dart';
import 'package:wheelathlete/state/sync_providers.dart';
import 'package:wheelathlete/theme/theme.dart';
import 'package:wheelathlete/ui/board_settings_page.dart';
import 'package:wheelathlete/widgets/connection_card.dart';
import 'package:wheelathlete/widgets/widgets.dart';

/// Python-parity Dashboard:
/// - Quick sensor summary cards for L, R, C
/// - System actions: Scan, Sync clocks, Refresh
/// - Board settings card (Rate, Accel, Gyro ranges)
/// - Nearby WheelAthlete devices table with connect/disconnect
class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connState = ref.watch(connectionManagerProvider);
    final manager = ref.read(connectionManagerProvider.notifier);
    final settings = ref.watch(dashboardSettingsProvider);
    final settingsNotifier = ref.read(dashboardSettingsProvider.notifier);
    final sync = ref.read(syncEngineProvider.notifier);
    final theme = Theme.of(context);

    final anyConnected = connState.bySide.values.any(
      (c) => c.status == ConnectionStatus.connected,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            tooltip: 'Go to Acquisition',
            icon: const Icon(Icons.sensors_rounded),
            onPressed: () => ref.read(homeTabIndexProvider.notifier).setTab(HomeTabNotifier.acquisition),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          if (!connState.isScanning) {
            await manager.startScan();
          }
        },
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            // Top action buttons
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: connState.isScanning ? null : () => manager.startScan(),
                    icon: Icon(connState.isScanning ? Icons.hourglass_top_rounded : Icons.bluetooth_searching_rounded),
                    label: Text(connState.isScanning ? 'Scanning…' : 'Scan Sensors'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                OutlinedButton.icon(
                  onPressed: anyConnected
                      ? () async {
                          for (final side in WheelSide.values) {
                            if (connState.bySide[side]?.status == ConnectionStatus.connected) {
                              try {
                                await sync.synchronize(side);
                              } on Object catch (_) {}
                            }
                          }
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Clock sync completed for connected sensors.')),
                            );
                          }
                        }
                      : null,
                  icon: const Icon(Icons.sync_rounded),
                  label: const Text('Sync Clocks'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),

            // Sensor Summary Cards (L, R, C)
            Text('Sensors (L / R / C)', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Column(
              children: [
                for (final side in WheelSide.values) ...[
                  ConnectionCard(
                    side: side,
                    status: connState.bySide[side]!.status,
                    deviceName: connState.bySide[side]!.deviceName,
                    batteryPercent: connState.bySide[side]!.batteryPercent,
                    rssi: connState.bySide[side]!.rssi,
                    onSettings: connState.bySide[side]!.status == ConnectionStatus.connected
                        ? () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => BoardSettingsPage(side: side),
                              ),
                            )
                        : null,
                    onDisconnect: connState.bySide[side]!.status == ConnectionStatus.connected
                        ? () => manager.disconnect(side)
                        : null,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
              ],
            ),

            const SizedBox(height: AppSpacing.md),

            // Fast Board Configuration Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.tune_rounded),
                        const SizedBox(width: AppSpacing.xs),
                        Text('Board Settings', style: theme.textTheme.titleSmall),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.md,
                      runSpacing: AppSpacing.sm,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        // Rate
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('Rate: '),
                            DropdownButton<int>(
                              value: settings.rateHz,
                              underline: const SizedBox(),
                              items: const [
                                DropdownMenuItem(value: 50, child: Text('50 Hz')),
                                DropdownMenuItem(value: 100, child: Text('100 Hz')),
                                DropdownMenuItem(value: 200, child: Text('200 Hz')),
                              ],
                              onChanged: (val) {
                                if (val != null) settingsNotifier.setRate(val);
                              },
                            ),
                          ],
                        ),
                        // Accel range
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('Accel: '),
                            DropdownButton<int>(
                              value: settings.accelRange,
                              underline: const SizedBox(),
                              items: const [
                                DropdownMenuItem(value: 0, child: Text('±2g')),
                                DropdownMenuItem(value: 1, child: Text('±4g')),
                                DropdownMenuItem(value: 2, child: Text('±8g')),
                                DropdownMenuItem(value: 3, child: Text('±16g')),
                              ],
                              onChanged: (val) {
                                if (val != null) settingsNotifier.setAccelRange(val);
                              },
                            ),
                          ],
                        ),
                        // Gyro range
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('Gyro: '),
                            DropdownButton<int>(
                              value: settings.gyroRange,
                              underline: const SizedBox(),
                              items: const [
                                DropdownMenuItem(value: 0, child: Text('±250°/s')),
                                DropdownMenuItem(value: 1, child: Text('±500°/s')),
                                DropdownMenuItem(value: 2, child: Text('±1000°/s')),
                                DropdownMenuItem(value: 3, child: Text('±2000°/s')),
                              ],
                              onChanged: (val) {
                                if (val != null) settingsNotifier.setGyroRange(val);
                              },
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
                        OutlinedButton(
                          onPressed: connState.bySide[WheelSide.left]?.status == ConnectionStatus.connected
                              ? () => settingsNotifier.applyToSide(WheelSide.left)
                              : null,
                          child: const Text('Apply L'),
                        ),
                        OutlinedButton(
                          onPressed: connState.bySide[WheelSide.right]?.status == ConnectionStatus.connected
                              ? () => settingsNotifier.applyToSide(WheelSide.right)
                              : null,
                          child: const Text('Apply R'),
                        ),
                        OutlinedButton(
                          onPressed: connState.bySide[WheelSide.center]?.status == ConnectionStatus.connected
                              ? () => settingsNotifier.applyToSide(WheelSide.center)
                              : null,
                          child: const Text('Apply C'),
                        ),
                        FilledButton.tonal(
                          onPressed: anyConnected ? () => settingsNotifier.applyToAllConnected() : null,
                          child: const Text('Apply Connected'),
                        ),
                      ],
                    ),
                    if (settings.feedbackMessage != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        settings.feedbackMessage!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: AppSpacing.md),

            // Nearby WheelAthlete Peripherals
            Text('Discovered Devices', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            if (connState.scanResults.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: Center(
                  child: Text(
                    connState.isScanning
                        ? 'Scanning for sensors…'
                        : 'No new devices found. Tap Scan Sensors above.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else
              for (final device in connState.scanResults)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.sensors_rounded),
                    title: Text(device.name.isEmpty ? device.id : device.name),
                    subtitle: Text('${device.id} · ${device.rssi} dBm'),
                    trailing: FilledButton.tonal(
                      onPressed: () => manager.connect(device.id),
                      child: const Text('Connect'),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
