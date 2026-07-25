import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wheelathlete/state/ble_providers.dart';
import 'package:wheelathlete/state/home_providers.dart';
import 'package:wheelathlete/state/imu_providers.dart';
import 'package:wheelathlete/state/live_acquisition_providers.dart';
import 'package:wheelathlete/theme/theme.dart';
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
    final live = ref.watch(liveAcquisitionProvider);

    // Use `select` so the page shell only rebuilds on connection/streaming
    // status changes, not on every IMU sample. The per-wheel panels subscribe
    // to their own side data below.
    final anyConnected = ref.watch(
      connectionManagerProvider.select(
        (s) =>
            s.bySide.values.any((c) => c.status == ConnectionStatus.connected),
      ),
    );
    final anyStreaming = live.active;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live IMU'),
        actions: [
          IconButton(
            onPressed: anyConnected
                ? () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const RecordPage()),
                  )
                : null,
            icon: const Icon(Icons.fiber_manual_record_rounded),
            tooltip: 'Record',
          ),
          IconButton(
            onPressed: () => ref.read(homeTabIndexProvider.notifier).setTab(2),
            icon: const Icon(Icons.folder_open_rounded),
            tooltip: 'Browse',
          ),
        ],
      ),
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _WheelPanel(side: WheelSide.left),
            SizedBox(height: AppSpacing.md),
            _WheelPanel(side: WheelSide.right),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: startButtonKey,
        onPressed: anyConnected && live.canToggle
            ? () => anyStreaming
                  ? ref.read(liveAcquisitionProvider.notifier).stop()
                  : ref.read(liveAcquisitionProvider.notifier).start()
            : null,
        icon: Icon(
          anyStreaming || live.status == LiveAcquisitionStatus.stopping
              ? Icons.stop_rounded
              : Icons.play_arrow_rounded,
        ),
        label: Text(
          anyStreaming || live.status == LiveAcquisitionStatus.stopping
              ? 'Stop'
              : 'Start',
        ),
      ),
    );
  }
}

class _WheelPanel extends ConsumerWidget {
  const _WheelPanel({required this.side});
  final WheelSide side;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connection = ref.watch(
      connectionManagerProvider.select((s) => s.bySide[side]!),
    );
    final imuState = ref.watch(
      imuStreamProvider.select((s) => s.bySide[side]!),
    );
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
            _PanelHeader(
              side: side,
              connection: connection,
              imuState: imuState,
            ),
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
        Text(
          label,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: role.onContainer,
            fontWeight: FontWeight.bold,
          ),
        ),
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
    return Icon(
      Icons.circle,
      size: 10,
      color: Theme.of(context).colorScheme.error,
    );
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
        // Realtime scrolling line charts: accel above gyro, each with a
        // section label and per-axis legend (x/y/z).
        _ChartLabel(title: 'Accelerometer (g)', axisColors: axisColors),
        const SizedBox(height: AppSpacing.xxs),
        ImuChart(
          readings: imuState.recent,
          isAccel: true,
          axisColors: axisColors,
        ),
        const SizedBox(height: AppSpacing.xs),
        _ChartLabel(title: 'Gyroscope (°/s)', axisColors: axisColors),
        const SizedBox(height: AppSpacing.xxs),
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
            LiveMetricTile(
              label: 'Accel X',
              value: r.ax,
              unit: 'g',
              side: side,
            ),
            LiveMetricTile(
              label: 'Accel Y',
              value: r.ay,
              unit: 'g',
              side: side,
            ),
            LiveMetricTile(
              label: 'Accel Z',
              value: r.az,
              unit: 'g',
              side: side,
            ),
            LiveMetricTile(
              label: 'Gyro X',
              value: r.gx,
              unit: '°/s',
              side: side,
            ),
            LiveMetricTile(
              label: 'Gyro Y',
              value: r.gy,
              unit: '°/s',
              side: side,
            ),
            LiveMetricTile(
              label: 'Gyro Z',
              value: r.gz,
              unit: '°/s',
              side: side,
            ),
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
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
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

/// Section label above each IMU chart: shows the sensor name (Accelerometer
/// / Gyroscope) and a small x/y/z color legend so the user can tell which
/// line is which axis.
class _ChartLabel extends StatelessWidget {
  const _ChartLabel({required this.title, required this.axisColors});
  final String title;
  final List<Color> axisColors;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    const axes = ['x', 'y', 'z'];
    return Row(
      children: [
        Text(
          title,
          style: theme.textTheme.labelMedium?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        for (var i = 0; i < 3; i++) ...[
          Container(
            width: 10,
            height: 3,
            decoration: BoxDecoration(
              color: axisColors[i],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 2),
          Text(
            axes[i],
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (i < 2) const SizedBox(width: AppSpacing.sm),
        ],
      ],
    );
  }
}
