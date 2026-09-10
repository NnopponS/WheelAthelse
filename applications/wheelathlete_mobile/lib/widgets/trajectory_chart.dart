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

class TrajectoryChart extends StatefulWidget {
  const TrajectoryChart({
    super.key,
    required this.points,
    this.selectedIndex,
    this.windowStart,
    this.windowEnd,
  });
  final List<TrajectoryPoint> points;
  final int? selectedIndex;
  final int? windowStart;
  final int? windowEnd;
  @override
  State<TrajectoryChart> createState() => _TrajectoryChartState();
}

class _TrajectoryChartState extends State<TrajectoryChart> {
  late TrajectoryBounds _bounds;
  List<FlSpot> _spots = const [];
  List<FlSpot> _window = const [];

  @override
  void initState() {
    super.initState();
    _cache();
  }

  @override
  void didUpdateWidget(covariant TrajectoryChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.points, widget.points)) {
      _cache();
    } else if (oldWidget.windowStart != widget.windowStart ||
        oldWidget.windowEnd != widget.windowEnd) {
      _cacheWindow();
    }
  }

  void _cache() {
    _bounds = squareTrajectoryBounds(
      widget.points,
    ); // Bounds always use ALL points.
    final stride = math.max(1, (widget.points.length / 2500).ceil());
    _spots = [
      for (var i = 0; i < widget.points.length; i += stride)
        FlSpot(widget.points[i].x, widget.points[i].y),
    ];
    if (widget.points.isNotEmpty) {
      _spots.add(FlSpot(widget.points.last.x, widget.points.last.y));
    }
    _cacheWindow();
  }

  void _cacheWindow() {
    final a = widget.windowStart, b = widget.windowEnd;
    if (a == null || b == null || a < 0 || b >= widget.points.length || b < a) {
      _window = const [];
      return;
    }
    final stride = math.max(1, ((b - a + 1) / 2000).ceil());
    _window = [
      for (var i = a; i <= b; i += stride)
        FlSpot(widget.points[i].x, widget.points[i].y),
    ];
    _window.add(FlSpot(widget.points[b].x, widget.points[b].y));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final wc = context.wheelColors;
    final index = widget.selectedIndex;
    final cursor = index != null && index >= 0 && index < widget.points.length
        ? widget.points[index]
        : null;
    LineChartBarData dot(FlSpot p, Color color) => LineChartBarData(
      spots: [p],
      color: color,
      barWidth: 0,
      isCurved: false,
      dotData: const FlDotData(show: true),
    );
    return Semantics(
      label:
          'Estimated trajectory. Equal X and Y scales in metres. Cursor and window follow the time controls.',
      child: AspectRatio(
        aspectRatio: 1,
        child: LineChart(
          duration: Duration.zero,
          LineChartData(
            minX: _bounds.minX,
            maxX: _bounds.maxX,
            minY: _bounds.minY,
            maxY: _bounds.maxY,
            lineBarsData: [
              LineChartBarData(
                spots: _spots,
                color: scheme.primary,
                barWidth: 2,
                isCurved: false,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(show: false),
              ),
              if (_window.isNotEmpty)
                LineChartBarData(
                  spots: _window,
                  color: scheme.tertiary,
                  barWidth: 3,
                  isCurved: false,
                  dashArray: [5, 3],
                  dotData: const FlDotData(show: false),
                ),
              if (_spots.isNotEmpty) dot(_spots.first, wc.left.solid),
              if (_spots.length > 1) dot(_spots.last, wc.right.solid),
              if (cursor != null)
                dot(FlSpot(cursor.x, cursor.y), scheme.onSurface),
            ],
            titlesData: const FlTitlesData(show: false),
            gridData: FlGridData(
              show: true,
              getDrawingHorizontalLine: (_) =>
                  FlLine(color: wc.chartGrid, strokeWidth: .5),
              getDrawingVerticalLine: (_) =>
                  FlLine(color: wc.chartGrid, strokeWidth: .5),
            ),
            borderData: FlBorderData(
              show: true,
              border: Border.all(color: scheme.outlineVariant),
            ),
            lineTouchData: const LineTouchData(enabled: true),
            clipData: const FlClipData.all(),
          ),
        ),
      ),
    );
  }
}
