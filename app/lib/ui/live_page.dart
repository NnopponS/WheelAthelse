import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wheelathlete/state/ble_providers.dart';
import 'package:wheelathlete/state/imu_providers.dart';
import 'package:wheelathlete/theme/theme.dart';
import 'package:wheelathlete/ui/browse_page.dart';
import 'package:wheelathlete/ui/record_page.dart';
import 'package:wheelathlete/widgets/widgets.dart';

/// Realtime IMU display: shows live accel/gyro values for both wheels using
/// the design system's [LiveMetricTile]s with per-side identity colors.
///
/// A single Start/Stop FAB toggles streaming for both connected wheels at
/// once. Each panel shows the latest [ImuReading], sample count, and drop
/// count (seq-gap indicator). When a wheel is not connected, its panel shows
/// a "Not connected" hint instead of metrics.
class LivePage extends ConsumerWidget {
  const LivePage({super.key});

  static final Key startButtonKey = UniqueKey();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conn = ref.watch(connectionManagerProvider);
    final imu = ref.watch(imuStreamProvider);
    final notifier = ref.read(imuStreamProvider.notifier);

    final anyConnected =
        conn.bySide.values.any((c) => c.status == ConnectionStatus.connected);
    final anyStreaming =
        imu.bySide.values.any((s) => s.streaming);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live IMU'),
        actions: [
          IconButton(
            onPressed: anyConnected
                ? () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const RecordPage(),
                      ),
                    )
                : null,
            icon: const Icon(Icons.fiber_manual_record_rounded),
            tooltip: 'Record',
          ),
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const BrowsePage(),
              ),
            ),
            icon: const Icon(Icons.folder_open_rounded),
            tooltip: 'Browse',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _WheelPanel(side: WheelSide.left, conn: conn, imu: imu),
            const SizedBox(height: AppSpacing.md),
            _WheelPanel(side: WheelSide.right, conn: conn, imu: imu),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: startButtonKey,
        onPressed: anyConnected
            ? () => _toggleAll(notifier, anyStreaming, conn)
            : null,
        icon: Icon(anyStreaming ? Icons.stop_rounded : Icons.play_arrow_rounded),
        label: Text(anyStreaming ? 'Stop' : 'Start'),
      ),
    );
  }

  Future<void> _toggleAll(
    ImuStreamNotifier notifier,
    bool anyStreaming,
    ConnectionManagerState conn,
  ) async {
    for (final side in WheelSide.values) {
      if (conn.bySide[side]!.status == ConnectionStatus.connected) {
        if (anyStreaming) {
          await notifier.stop(side);
        } else {
          await notifier.start(side);
        }
      }
    }
  }
}

class _WheelPanel extends StatelessWidget {
  const _WheelPanel({required this.side, required this.conn, required this.imu});
  final WheelSide side;
  final ConnectionManagerState conn;
  final ImuStreamState imu;

  @override
  Widget build(BuildContext context) {
    final connection = conn.bySide[side]!;
    final imuState = imu.bySide[side]!;
    final wc = context.wheelColors;
    final role = wc.forWheel(side);

    // Per-axis colors from the design system: x = wheel identity, y = success,
    // z = warning. Distinct within each chart and consistent across wheels.
    final axisColors = [role.solid, wc.success.solid, wc.warning.solid];

    return Card(
      color: role.container,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PanelHeader(side: side, connection: connection, imuState: imuState),
            const SizedBox(height: AppSpacing.sm),
            if (connection.status != ConnectionStatus.connected)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Text('Not connected'),
              )
            else
              _MetricGrid(
                imuState: imuState,
                side: side,
                axisColors: axisColors,
              ),
            if (imuState.error != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  imuState.error!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({
    required this.side,
    required this.connection,
    required this.imuState,
  });
  final WheelSide side;
  final WheelConnection connection;
  final WheelImuState imuState;

  @override
  Widget build(BuildContext context) {
    final wc = context.wheelColors;
    final role = wc.forWheel(side);
    final label = side == WheelSide.left ? 'Left wheel' : 'Right wheel';

    return Row(
      children: [
        StatusBadge(
          label: side == WheelSide.left ? 'L' : 'R',
          tone: side == WheelSide.left ? BadgeTone.left : BadgeTone.right,
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(label, style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: role.onContainer,
              fontWeight: FontWeight.bold,
            )),
        const Spacer(),
        if (imuState.streaming)
          const _LiveDot()
        else if (imuState.error != null)
          Icon(Icons.error_outline_rounded, color: wc.danger.solid, size: 20),
      ],
    );
  }
}

class _LiveDot extends StatelessWidget {
  const _LiveDot();

  @override
  Widget build(BuildContext context) {
    // Static red dot — a blinking animation would make pumpAndSettle time
    // out in tests (the frame loop never quiesces). The streaming state is
    // already conveyed by the FAB label + sample counter.
    return Icon(Icons.circle, size: 10, color: Theme.of(context).colorScheme.error);
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({
    required this.imuState,
    required this.side,
    required this.axisColors,
  });
  final WheelImuState imuState;
  final WheelSide side;
  final List<Color> axisColors;

  @override
  Widget build(BuildContext context) {
    final r = imuState.latest;
    if (r == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Text(
          imuState.streaming ? 'Waiting for data…' : 'Stopped',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Realtime scrolling line charts (subtask #19): accel above gyro.
        ImuChart(
          readings: imuState.recent,
          isAccel: true,
          axisColors: axisColors,
        ),
        const SizedBox(height: AppSpacing.xs),
        ImuChart(
          readings: imuState.recent,
          isAccel: false,
          axisColors: axisColors,
        ),
        const SizedBox(height: AppSpacing.sm),
        // Compact numeric tile summary retained below the charts.
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            LiveMetricTile(label: 'ax', value: r.ax, unit: 'g', side: side),
            LiveMetricTile(label: 'ay', value: r.ay, unit: 'g', side: side),
            LiveMetricTile(label: 'az', value: r.az, unit: 'g', side: side),
            LiveMetricTile(label: 'gx', value: r.gx, unit: '°/s', side: side),
            LiveMetricTile(label: 'gy', value: r.gy, unit: '°/s', side: side),
            LiveMetricTile(label: 'gz', value: r.gz, unit: '°/s', side: side),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        _StatsLine(imuState: imuState),
      ],
    );
  }
}

class _StatsLine extends StatelessWidget {
  const _StatsLine({required this.imuState});
  final WheelImuState imuState;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: AppSpacing.md,
      children: [
        Text(
          '${imuState.sampleCount} samples',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
        if (imuState.dropCount > 0)
          Text(
            '${imuState.dropCount} dropped',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.bold,
                ),
          ),
      ],
    );
  }
}
