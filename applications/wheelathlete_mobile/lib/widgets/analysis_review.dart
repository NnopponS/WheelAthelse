import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:wheelathlete/export/analysis_export.dart';
import 'package:wheelathlete/export/export_providers.dart';
import 'package:wheelathlete/model/analysis_contract.dart';
import 'package:wheelathlete/model/trajectory_model.dart';
import 'package:wheelathlete/widgets/trajectory_chart.dart';

const _channels = <String, (String, double)>{
  'speed_mps': ('Speed magnitude (m/s)', 1.0),
  'signed_speed_mps': ('Signed forward speed (m/s)', 1.0),
  'longitudinal_accel_mps2': ('Longitudinal acceleration (m/s2)', 1.0),
  'yaw_rad': ('Unwrapped chair yaw (deg)', 180 / math.pi),
  'yaw_rate_radps': ('Yaw rate (deg/s)', 180 / math.pi),
  'speed_change_mps2': ('Speed-magnitude change (m/s2)', 1.0),
};

String _format(double? v, [String unit = '']) =>
    v == null ? 'Unavailable' : '${v.toStringAsFixed(3)}$unit';

class AnalysisReview extends StatefulWidget {
  const AnalysisReview({
    super.key,
    required this.analysis,
    required this.points,
    this.pickExportDirectory,
  });
  final KinematicAnalysis analysis;
  final List<TrajectoryPoint> points;
  final Future<String?> Function()? pickExportDirectory;
  @override
  State<AnalysisReview> createState() => _AnalysisReviewState();
}

class _AnalysisReviewState extends State<AnalysisReview> {
  var _cursor = 0, _start = 0, _stop = 0;
  var _field = 'speed_mps';
  var _exporting = false;
  String? _exportStatus;
  late Map<String, dynamic> _statistics;

  @override
  void initState() {
    super.initState();
    _reset();
  }

  @override
  void didUpdateWidget(covariant AnalysisReview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.analysis, widget.analysis)) _reset();
  }

  void _reset() {
    _cursor = 0;
    _start = 0;
    _stop = widget.analysis.samples.length - 1;
    _exportStatus = null;
    _updateStatistics();
  }

  void _updateStatistics() {
    final samples = widget.analysis.samples;
    _statistics = widget.analysis.windowStatistics(
      samples[_start].timeS,
      samples[_stop].timeS,
    );
  }

  void _range(RangeValues value) => setState(() {
    _start = value.start.round();
    _stop = value.end.round();
    _updateStatistics();
  });

  Future<void> _export() async {
    if (_exporting) return;
    final analysis = widget.analysis;
    final start = analysis.samples[_start].timeS,
        stop = analysis.samples[_stop].timeS;
    setState(() {
      _exporting = true;
      _exportStatus = null;
    });
    try {
      final dir = await (widget.pickExportDirectory ?? pickDirectory)();
      if (dir == null) return;
      final out = await saveAnalysis(
        analysis,
        Directory(dir),
        startS: start,
        stopS: stop,
      );
      if (!mounted || !identical(analysis, widget.analysis)) return;
      setState(
        () =>
            _exportStatus = 'Saved timeline.csv + metadata.json to ${out.path}',
      );
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _exportStatus = 'Export failed: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.analysis, samples = a.samples;
    final row = samples[_cursor];
    final theme = Theme.of(context);
    final yaw = row['yaw_rad'], rate = row['yaw_rate_radps'];
    final speedStats = (_statistics['metrics'] as Map)['speed_mps'] as Map;
    final max = (samples.length - 1).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Offline coaching review - experimental',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Text(
          'No physical accuracy or synchronization certification. Missing quantities stay unavailable.',
          style: theme.textTheme.bodySmall,
        ),
        RepaintBoundary(
          child: TrajectoryChart(
            points: widget.points,
            selectedIndex: _cursor,
            windowStart: _start,
            windowEnd: _stop,
          ),
        ),
        Text(
          'X/Y: metres, ${a.metadata['xy_frame'] ?? 'declared initial frame'}. Cursor is the exact source point.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Text(
          'Time ${row.timeS.toStringAsFixed(3)} s | sample ${_cursor + 1}/${samples.length}',
          key: const Key('analysisSelectedTime'),
        ),
        Slider(
          key: const Key('analysisTimeSlider'),
          min: 0,
          max: max,
          value: _cursor.toDouble(),
          semanticFormatterCallback: (v) =>
              '${samples[v.round()].timeS.toStringAsFixed(3)} seconds',
          onChanged: (v) => setState(() => _cursor = v.round()),
        ),
        Text(
          'Signed speed: ${_format(row['signed_speed_mps'], ' m/s')}\n'
          'Speed magnitude: ${_format(row['speed_mps'], ' m/s')}\n'
          'Longitudinal acceleration: ${_format(row['longitudinal_accel_mps2'], ' m/s2')}\n'
          'Chair yaw: ${_format(yaw == null ? null : yaw * 180 / math.pi, ' deg')}\n'
          'Yaw rate: ${_format(rate == null ? null : rate * 180 / math.pi, ' deg/s')}',
          key: const Key('analysisSelectedMetrics'),
        ),
        const SizedBox(height: 8),
        Text(
          row.qualityFlags.isEmpty
              ? 'No local input flag; estimate remains unvalidated.'
              : 'Quality flags: ${row.qualityFlags.join(', ')}',
          key: const Key('analysisQualityStatus'),
          style: theme.textTheme.bodySmall,
        ),
        DropdownButton<String>(
          key: const Key('analysisChannel'),
          isExpanded: true,
          value: _field,
          items: _channels.entries
              .map(
                (e) => DropdownMenuItem(
                  value: e.key,
                  child: Text(
                    e.value.$1,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: (v) {
            if (v != null) setState(() => _field = v);
          },
        ),
        _AnalysisTimePlot(
          analysis: a,
          field: _field,
          cursor: row.timeS,
          start: samples[_start].timeS,
          stop: samples[_stop].timeS,
        ),
        const SizedBox(height: 8),
        Text(
          'Window ${samples[_start].timeS.toStringAsFixed(3)} - ${samples[_stop].timeS.toStringAsFixed(3)} s',
        ),
        RangeSlider(
          key: const Key('analysisWindowSlider'),
          min: 0,
          max: max,
          values: RangeValues(_start.toDouble(), _stop.toDouble()),
          labels: RangeLabels(
            samples[_start].timeS.toStringAsFixed(3),
            samples[_stop].timeS.toStringAsFixed(3),
          ),
          semanticFormatterCallback: (v) =>
              '${samples[v.round()].timeS.toStringAsFixed(3)} seconds',
          onChanged: _range,
        ),
        Text(
          '${_statistics['samples']} samples | ${(_statistics['duration_s'] as num).toStringAsFixed(3)} s\n'
          '${(_statistics['path_length_m'] as num).toStringAsFixed(3)} m estimated window path\n'
          'Mean speed ${_format((speedStats['mean'] as num?)?.toDouble(), ' m/s')} | '
          'max ${_format((speedStats['max'] as num?)?.toDouble(), ' m/s')}',
          key: const Key('analysisWindowSummary'),
        ),
        Text(
          'Full-resolution, time-weighted statistics. No pose reset or derivative recomputation for the selected window.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            OutlinedButton(
              onPressed: () => _range(RangeValues(0, max)),
              child: const Text('Full window'),
            ),
            FilledButton.icon(
              key: const Key('exportAnalysisButton'),
              onPressed: _exporting ? null : _export,
              icon: const Icon(Icons.save_alt),
              label: Text(_exporting ? 'Exporting...' : 'Export analysis'),
            ),
          ],
        ),
        if (_exportStatus != null)
          Text(_exportStatus!, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class _AnalysisTimePlot extends StatefulWidget {
  const _AnalysisTimePlot({
    required this.analysis,
    required this.field,
    required this.cursor,
    required this.start,
    required this.stop,
  });
  final KinematicAnalysis analysis;
  final String field;
  final double cursor, start, stop;
  @override
  State<_AnalysisTimePlot> createState() => _AnalysisTimePlotState();
}

class _AnalysisTimePlotState extends State<_AnalysisTimePlot> {
  List<List<FlSpot>> _runs = const [];
  double _min = -1, _max = 1;
  @override
  void initState() {
    super.initState();
    _cache();
  }

  @override
  void didUpdateWidget(covariant _AnalysisTimePlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.analysis, widget.analysis) ||
        oldWidget.field != widget.field) {
      _cache();
    }
  }

  void _cache() {
    final runs = <List<FlSpot>>[], values = <double>[];
    var run = <FlSpot>[];
    final scale = _channels[widget.field]!.$2;
    void finish() {
      if (run.isEmpty) return;
      final stride = math.max(1, (run.length / 2000).ceil());
      final draw = [for (var i = 0; i < run.length; i += stride) run[i]];
      draw.add(run.last);
      runs.add(draw);
      run = [];
    }

    for (final sample in widget.analysis.samples) {
      final value = sample[widget.field];
      if (value == null) {
        finish();
      } else {
        values.add(value * scale);
        run.add(FlSpot(sample.timeS, value * scale));
      }
    }
    finish();
    _runs = runs;
    if (values.isEmpty) {
      _min = -1;
      _max = 1;
      return;
    }
    final low = values.reduce(math.min), high = values.reduce(math.max);
    final pad = math.max((high - low) * .08, .05);
    _min = low - pad;
    _max = high + pad;
  }

  @override
  Widget build(BuildContext context) {
    if (_runs.isEmpty) {
      return const SizedBox(
        height: 80,
        child: Center(
          child: Text('Unavailable for this model or data support'),
        ),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final samples = widget.analysis.samples;
    return Column(
      children: [
        SizedBox(
          height: 170,
          child: LineChart(
            duration: Duration.zero,
            LineChartData(
              minX: samples.first.timeS,
              maxX: samples.last.timeS,
              minY: _min,
              maxY: _max,
              lineBarsData: _runs
                  .map(
                    (r) => LineChartBarData(
                      spots: r,
                      color: scheme.primary,
                      barWidth: 2,
                      isCurved: false,
                      dotData: const FlDotData(show: false),
                    ),
                  )
                  .toList(),
              extraLinesData: ExtraLinesData(
                verticalLines: [
                  VerticalLine(
                    x: widget.cursor,
                    color: scheme.onSurface,
                    strokeWidth: 1.5,
                  ),
                  VerticalLine(
                    x: widget.start,
                    color: scheme.tertiary,
                    strokeWidth: 1,
                    dashArray: [5, 3],
                  ),
                  VerticalLine(
                    x: widget.stop,
                    color: scheme.tertiary,
                    strokeWidth: 1,
                    dashArray: [5, 3],
                  ),
                ],
              ),
              titlesData: const FlTitlesData(show: false),
              borderData: FlBorderData(
                show: true,
                border: Border.all(color: scheme.outlineVariant),
              ),
              clipData: const FlClipData.all(),
            ),
          ),
        ),
        Text(
          '${samples.first.timeS.toStringAsFixed(2)} - ${samples.last.timeS.toStringAsFixed(2)} seconds | '
          'Y ${_min.toStringAsFixed(2)} - ${_max.toStringAsFixed(2)}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
