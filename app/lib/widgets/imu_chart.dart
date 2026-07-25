import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'package:wheelathlete/ble/imu_packet.dart';
import 'package:wheelathlete/theme/theme.dart';

/// Pure logic for the realtime IMU chart: a rolling ring buffer of recent
/// [ImuReading]s with window trimming + decimation so the chart never plots
/// more than ~50-100 points per axis (avoids jank at 100 Hz).
///
/// All methods are static and side-effect free so they can be unit-tested
/// without Flutter.
class ImuChartBuffer {
  const ImuChartBuffer._();

  /// Keeps the last [max] readings (drops older entries from the front).
  static List<ImuReading> cap(List<ImuReading> readings, int max) {
    if (readings.length <= max) return List<ImuReading>.of(readings);
    return readings.sublist(readings.length - max);
  }

  /// Keeps only readings whose `tDeviceUs` is within [windowUs] microseconds
  /// of the most recent reading. Used to render a rolling ~5s window.
  static List<ImuReading> trimToWindowMs(
    List<ImuReading> readings,
    int windowUs,
  ) {
    if (readings.isEmpty) return const [];
    final latest = readings.last.tDeviceUs;
    final cutoff = latest - windowUs;
    // Find the first reading at or after the cutoff. tDeviceUs is monotonic
    // within a 5s window (wraps at ~71 min, far longer than our window).
    for (var i = 0; i < readings.length; i++) {
      if (readings[i].tDeviceUs >= cutoff) {
        return readings.sublist(i);
      }
    }
    return [readings.last];
  }

  /// Downsamples [readings] to exactly [targetPoints] evenly-spaced samples,
  /// always preserving the first and last. Returns the input unchanged when
  /// it's already at or below [targetPoints].
  static List<ImuReading> decimate(
    List<ImuReading> readings,
    int targetPoints,
  ) {
    if (readings.length <= targetPoints) return List<ImuReading>.of(readings);
    if (targetPoints <= 1) return [readings.last];
    final n = readings.length;
    final out = <ImuReading>[];
    for (var k = 0; k < targetPoints; k++) {
      final idx = (k * (n - 1)) ~/ (targetPoints - 1);
      out.add(readings[idx]);
    }
    return out;
  }

  /// Maps readings to accel FlSpots: x = ms relative to the first reading,
  /// y = the chosen axis value. [axis] selects ax/ay/az (0/1/2).
  static List<FlSpot> toAccelSpots(List<ImuReading> readings, {int axis = 0}) {
    if (readings.isEmpty) return const [];
    final t0 = readings.first.tDeviceUs;
    return readings.map((r) {
      final y = switch (axis) {
        0 => r.ax,
        1 => r.ay,
        _ => r.az,
      };
      return FlSpot(((r.tDeviceUs - t0) / 1000).toDouble(), y);
    }).toList();
  }

  /// Maps readings to gyro FlSpots: x = ms relative to the first reading,
  /// y = the chosen axis value. [axis] selects gx/gy/gz (0/1/2).
  static List<FlSpot> toGyroSpots(List<ImuReading> readings, {int axis = 0}) {
    if (readings.isEmpty) return const [];
    final t0 = readings.first.tDeviceUs;
    return readings.map((r) {
      final y = switch (axis) {
        0 => r.gx,
        1 => r.gy,
        _ => r.gz,
      };
      return FlSpot(((r.tDeviceUs - t0) / 1000).toDouble(), y);
    }).toList();
  }
}

/// A realtime line chart for one IMU axis group (accel or gyro). Renders three
/// per-axis lines (x/y/z) using the design-system colors. Static — rebuilds on
/// data change with no infinite animation (LineChart duration is zero).
class ImuChart extends StatelessWidget {
  const ImuChart({
    super.key,
    required this.readings,
    required this.isAccel,
    required this.axisColors,
    this.windowUs = 5000000, // 5 s
    this.maxPoints = 300,
    this.targetPoints = 80,
    this.height = 120,
  });

  /// Recent readings (already capped to [maxPoints] by the caller or here).
  final List<ImuReading> readings;

  /// True for the accel chart (ax/ay/az), false for gyro (gx/gy/gz).
  final bool isAccel;

  /// Per-axis colors: [x, y, z].
  final List<Color> axisColors;

  final int windowUs;
  final int maxPoints;
  final int targetPoints;
  final double height;

  @override
  Widget build(BuildContext context) {
    final wc = context.wheelColors;
    var data = ImuChartBuffer.cap(readings, maxPoints);
    data = ImuChartBuffer.trimToWindowMs(data, windowUs);
    final plot = ImuChartBuffer.decimate(data, targetPoints);

    List<FlSpot> spots(int axis) => isAccel
        ? ImuChartBuffer.toAccelSpots(plot, axis: axis)
        : ImuChartBuffer.toGyroSpots(plot, axis: axis);

    final bars = <LineChartBarData>[
      for (var a = 0; a < 3; a++)
        LineChartBarData(
          spots: spots(a),
          color: axisColors[a],
          barWidth: 1.5,
          isCurved: false,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(show: false),
        ),
    ];

    return SizedBox(
      height: height,
      child: LineChart(
        duration: Duration.zero, // static — no animation (test-safe)
        LineChartData(
          lineBarsData: bars,
          minX: 0,
          maxX: windowUs / 1000.0,
          minY: null,
          maxY: null,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: _autoInterval(plot, isAccel),
            getDrawingHorizontalLine: (value) =>
                FlLine(color: wc.chartGrid, strokeWidth: 0.5),
          ),
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
          clipData: const FlClipData.all(),
        ),
      ),
    );
  }

  /// A rough y-axis grid interval based on the data range.
  double? _autoInterval(List<ImuReading> data, bool accel) {
    if (data.isEmpty) return null;
    var minV = double.infinity;
    var maxV = double.negativeInfinity;
    for (final r in data) {
      final vals = accel ? [r.ax, r.ay, r.az] : [r.gx, r.gy, r.gz];
      for (final v in vals) {
        if (v < minV) minV = v;
        if (v > maxV) maxV = v;
      }
    }
    final range = (maxV - minV).abs();
    if (range == 0) return accel ? 1.0 : 50.0;
    // Round to a nice step.
    final step = range / 4;
    if (step <= 0) return null;
    return step;
  }
}
