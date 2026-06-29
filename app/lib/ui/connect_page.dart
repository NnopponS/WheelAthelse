import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wheelathlete/ble/ble_repository.dart';
import 'package:wheelathlete/state/ble_providers.dart';
import 'package:wheelathlete/theme/theme.dart';
import 'package:wheelathlete/ui/live_page.dart';
import 'package:wheelathlete/widgets/widgets.dart';

/// Scan + connect screen: lists discovered WheelAthlete devices and shows
/// the live L/R connection status via two [ConnectionCard]s.
///
/// Tapping a found device calls `connect`; the side (L/R) is auto-assigned
/// from the device's `wheel_id` byte, so the user cannot wire a left sensor
/// to the right card by mistake.
class ConnectPage extends ConsumerWidget {
  const ConnectPage({super.key});

  static final Key scanButtonKey = UniqueKey();
  static final Key liveButtonKey = UniqueKey();
  static Key connectKey(String deviceId) => ValueKey('connect-$deviceId');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(connectionManagerProvider);
    final manager = ref.read(connectionManagerProvider.notifier);
    final anyConnected =
        state.bySide.values.any((c) => c.status == ConnectionStatus.connected);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect Wheels'),
        actions: [
          IconButton(
            tooltip: 'Live IMU',
            key: liveButtonKey,
            onPressed: anyConnected
                ? () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const LivePage(),
                      ),
                    )
                : null,
            icon: const Icon(Icons.show_chart_rounded),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: state.isScanning ? null : () => manager.startScan(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          _ConnectionPair(state: state),
          const SizedBox(height: AppSpacing.md),
          if (state.error != null) _ErrorBanner(message: state.error!),
          const SizedBox(height: AppSpacing.sm),
          _ScanSection(state: state, manager: manager),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: scanButtonKey,
        onPressed: state.isScanning ? null : () => manager.startScan(),
        icon: const Icon(Icons.bluetooth_searching_rounded),
        label: Text(state.isScanning ? 'Scanning…' : 'Scan'),
      ),
    );
  }
}

class _ConnectionPair extends StatelessWidget {
  const _ConnectionPair({required this.state});
  final ConnectionManagerState state;

  @override
  Widget build(BuildContext context) {
    final left = state.bySide[WheelSide.left]!;
    final right = state.bySide[WheelSide.right]!;
    return Column(
      children: [
        ConnectionCard(
          side: WheelSide.left,
          status: left.status,
          deviceName: left.deviceName,
          rssi: left.rssi,
        ),
        const SizedBox(height: AppSpacing.sm),
        ConnectionCard(
          side: WheelSide.right,
          status: right.status,
          deviceName: right.deviceName,
          rssi: right.rssi,
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final wc = context.wheelColors;
    return Card(
      color: wc.danger.container,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded, color: wc.danger.onContainer),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: wc.danger.onContainer,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanSection extends StatelessWidget {
  const _ScanSection({required this.state, required this.manager});
  final ConnectionManagerState state;
  final ConnectionManagerNotifier manager;

  @override
  Widget build(BuildContext context) {
    if (state.scanResults.isEmpty && !state.isScanning) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Center(
          child: Text(
            'Tap Scan to find WheelAthlete sensors.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Found devices', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: AppSpacing.xs),
        for (final d in state.scanResults)
          _DeviceRow(
            key: ValueKey(d.id),
            device: d,
            onConnect: () => manager.connect(d.id),
          ),
      ],
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    super.key,
    required this.device,
    required this.onConnect,
  });

  final ScannedDevice device;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.sensors_rounded),
        title: Text(device.name.isEmpty ? device.id : device.name),
        subtitle: Text('${device.id} · ${device.rssi} dBm'),
        trailing: FilledButton.tonal(
          key: ConnectPage.connectKey(device.id),
          onPressed: onConnect,
          child: const Text('Connect'),
        ),
      ),
    );
  }
}
