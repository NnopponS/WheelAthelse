import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:wheelathlete/model/trajectory_model.dart';
import 'package:wheelathlete/theme/theme.dart';

class TrajectoryBounds {
  const TrajectoryBounds({
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
  });

  final double minX;
  final double maxX;
  final double minY;
  final double maxY;

  double get xSpan => maxX - minX;
  double get ySpan => maxY - minY;
}

/// Returns equal numeric X/Y spans so a square chart means one pixel has the
/// same metric scale in both axes. This is the same visual invariant used by
/// the Windows trajectory page.
TrajectoryBounds squareTrajectoryBounds(List<TrajectoryPoint> points) {
  if (points.isEmpty) {
    return const TrajectoryBounds(minX: -1, maxX: 1, minY: -1, maxY: 1);
  }
  var minX = points.first.x;
  var maxX = points.first.x;
  var minY = points.first.y;
  var maxY = points.first.y;
  for (final point in points.skip(1)) {
    minX = math.min(minX, point.x);
    maxX = math.max(maxX, point.x);
    minY = math.min(minY, point.y);
    maxY = math.max(maxY, point.y);
  }
  final centerX = (minX + maxX) / 2;
  final centerY = (minY + maxY) / 2;
  final rawSpan = math.max(maxX - minX, maxY - minY);
  final span = math.max(rawSpan * 1.10, 0.10);
  final half = span / 2;
  return TrajectoryBounds(
    minX: centerX - half,
    maxX: centerX + half,
    minY: centerY - half,
    maxY: centerY + half,
  );
}

class TrajectoryChart extends StatelessWidget {
  const TrajectoryChart({super.key, required this.points});

  final List<TrajectoryPoint> points;

  @override
  Widget build(BuildContext context) {
    final bounds = squareTrajectoryBounds(points);
    final scheme = Theme.of(context).colorScheme;
    final wc = context.wheelColors;
    final spots = points.map((point) => FlSpot(point.x, point.y)).toList();
    final start = spots.isEmpty ? const <FlSpot>[] : [spots.first];
    final end = spots.length < 2 ? const <FlSpot>[] : [spots.last];

    return AspectRatio(
      aspectRatio: 1,
      child: LineChart(
        duration: Duration.zero,
        LineChartData(
          minX: bounds.minX,
          maxX: bounds.maxX,
          minY: bounds.minY,
          maxY: bounds.maxY,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              color: scheme.primary,
              barWidth: 2,
              isCurved: false,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(show: false),
            ),
            if (start.isNotEmpty)
              LineChartBarData(
                spots: start,
                color: wc.left.solid,
                barWidth: 0,
                isCurved: false,
                dotData: const FlDotData(show: true),
              ),
            if (end.isNotEmpty)
              LineChartBarData(
                spots: end,
                color: wc.right.solid,
                barWidth: 0,
                isCurved: false,
                dotData: const FlDotData(show: true),
              ),
          ],
          titlesData: const FlTitlesData(show: false),
          gridData: FlGridData(
            show: true,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: wc.chartGrid, strokeWidth: 0.5),
            getDrawingVerticalLine: (_) =>
                FlLine(color: wc.chartGrid, strokeWidth: 0.5),
          ),
          borderData: FlBorderData(
            show: true,
            border: Border.all(color: scheme.outlineVariant),
          ),
          lineTouchData: const LineTouchData(enabled: true),
          clipData: const FlClipData.all(),
        ),
      ),
    );
  }
}
