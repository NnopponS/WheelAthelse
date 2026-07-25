import 'package:wheelathlete/records/session_model.dart';
import 'package:wheelathlete/theme/theme.dart';

/// CSV exporter for WheelAthlete session data (architecture.md §3).
///
/// Schema (two separate tables — one per wheel):
/// ```
/// # Wheel: L
/// seq,wheel,timestamp_app_ms,timestamp_utc_ms,
/// ax,ay,az,gx,gy,gz,marker
/// 0,L,...
/// 1,L,...
///
/// # Wheel: R
/// seq,wheel,timestamp_app_ms,timestamp_utc_ms,
/// ax,ay,az,gx,gy,gz,marker
/// 0,R,...
/// 1,R,...
/// ```
///
/// - L and R samples are written as **separate tables**, each with its own
///   header. Within each table, rows are sorted by `timestamp_utc_ms`.
/// - `wheel` column is `L` or `R`.
/// - `timestamp_utc_ms` is the absolute UTC epoch millisecond of the sample
///   (after clock-sync offset/drift correction). This is the column external
///   tools — e.g. aligning with an external camera recording — should use;
///   the raw on-device microsecond counter is not exported since it has no
///   meaning outside the originating wheel's own clock.
/// - `marker` is `1` when a Mark Event was active, `0` otherwise.
/// - Double values are formatted without unnecessary trailing zeros.
/// - Lines starting with `#` are section comments (skipped by parsers).
///
/// For large sessions, use [writeToSink] to stream to a file without building
/// the entire CSV string in memory.
class CsvExporter {
  const CsvExporter._();

  /// Internal/legacy session schema retained for on-device backward reads.
  static const String header =
      'seq,wheel,timestamp_app_ms,timestamp_utc_ms,'
      'ax,ay,az,gx,gy,gz,marker';

  /// Export schema 2: one lossless physical-units file per wheel.
  static const String rawHeader = 'time_us,ax_g,ay_g,az_g,gx_dps,gy_dps,gz_dps';

  /// Export schema 2: synchronized wide table for model training.
  static const String trainingHeader =
      'time_us,'
      'left_ax_g,left_ay_g,left_az_g,left_gx_dps,left_gy_dps,left_gz_dps,'
      'right_ax_g,right_ay_g,right_az_g,right_gx_dps,right_gy_dps,right_gz_dps';

  /// Section comment prefix for wheel tables.
  static const String commentPrefix = '#';

  /// Converts [samples] to a CSV string. L and R samples are written as
  /// separate tables. For large sessions, prefer [writeToSink] to avoid
  /// holding the entire file in memory.
  static String toCsvString(List<BufferedSample> samples) {
    final buf = StringBuffer();
    writeToSink(buf, samples);
    return buf.toString();
  }

  /// Produces the portable v1.2 trial format: one header followed by samples
  /// from every recorded wheel on a single corrected-time timeline.
  static String toCombinedCsvString(List<BufferedSample> samples) {
    final sorted = List<BufferedSample>.of(samples)
      ..sort((a, b) => a.timestampSyncedMs.compareTo(b.timestampSyncedMs));
    final sink = StringBuffer()..writeln(header);
    for (final sample in sorted) {
      sink.writeln(_formatRow(sample));
    }
    return sink.toString();
  }

  static String toRawCsvString(List<BufferedSample> samples, WheelSide side) {
    final sorted = samples.where((sample) => sample.wheel == side).toList()
      ..sort((a, b) => a.timestampSyncedMs.compareTo(b.timestampSyncedMs));
    final sink = StringBuffer()..writeln(rawHeader);
    for (final sample in sorted) {
      sink.writeln(
        [
          (sample.timestampSyncedMs * 1000).round(),
          _fmtDouble(sample.reading.ax),
          _fmtDouble(sample.reading.ay),
          _fmtDouble(sample.reading.az),
          _fmtDouble(sample.reading.gx),
          _fmtDouble(sample.reading.gy),
          _fmtDouble(sample.reading.gz),
        ].join(','),
      );
    }
    return sink.toString();
  }

  /// Interpolates both wheels onto an integer START-relative grid and emits
  /// the exact public training contract. No diagnostics or labels leak into
  /// the CSV; those belong in metadata.
  static String toAlignedTrainingCsvString(
    List<BufferedSample> samples, {
    int gridIntervalUs = 10000,
  }) {
    if (gridIntervalUs <= 0) {
      throw ArgumentError.value(gridIntervalUs, 'gridIntervalUs');
    }
    final left =
        samples.where((sample) => sample.wheel == WheelSide.left).toList()
          ..sort((a, b) => a.timestampSyncedMs.compareTo(b.timestampSyncedMs));
    final right =
        samples.where((sample) => sample.wheel == WheelSide.right).toList()
          ..sort((a, b) => a.timestampSyncedMs.compareTo(b.timestampSyncedMs));
    final sink = StringBuffer()..writeln(trainingHeader);
    if (left.isEmpty || right.isEmpty) return sink.toString();

    final startUs = _ceilToGrid(
      ((left.first.timestampSyncedMs > right.first.timestampSyncedMs
                  ? left.first.timestampSyncedMs
                  : right.first.timestampSyncedMs) *
              1000)
          .round(),
      gridIntervalUs,
    );
    final endUs =
        ((left.last.timestampSyncedMs < right.last.timestampSyncedMs
                    ? left.last.timestampSyncedMs
                    : right.last.timestampSyncedMs) *
                1000)
            .round();
    var leftIndex = 0;
    var rightIndex = 0;
    for (var timeUs = startUs; timeUs <= endUs; timeUs += gridIntervalUs) {
      final leftResult = _interpolate(left, leftIndex, timeUs);
      final rightResult = _interpolate(right, rightIndex, timeUs);
      if (leftResult == null || rightResult == null) continue;
      leftIndex = leftResult.$1;
      rightIndex = rightResult.$1;
      sink.writeln(
        [
          timeUs,
          ...leftResult.$2.map(_fmtDouble),
          ...rightResult.$2.map(_fmtDouble),
        ].join(','),
      );
    }
    return sink.toString();
  }

  static int _ceilToGrid(int value, int interval) =>
      ((value + interval - 1) ~/ interval) * interval;

  static (int, List<double>)? _interpolate(
    List<BufferedSample> samples,
    int startIndex,
    int timeUs,
  ) {
    var index = startIndex;
    while (index + 1 < samples.length &&
        (samples[index + 1].timestampSyncedMs * 1000).round() < timeUs) {
      index++;
    }
    if (index + 1 >= samples.length) return null;
    final a = samples[index];
    final b = samples[index + 1];
    final aUs = (a.timestampSyncedMs * 1000).round();
    final bUs = (b.timestampSyncedMs * 1000).round();
    if (timeUs < aUs || timeUs > bUs || bUs == aUs) return null;
    final ratio = (timeUs - aUs) / (bUs - aUs);
    double lerp(double x, double y) => x + (y - x) * ratio;
    return (
      index,
      [
        lerp(a.reading.ax, b.reading.ax),
        lerp(a.reading.ay, b.reading.ay),
        lerp(a.reading.az, b.reading.az),
        lerp(a.reading.gx, b.reading.gx),
        lerp(a.reading.gy, b.reading.gy),
        lerp(a.reading.gz, b.reading.gz),
      ],
    );
  }

  /// Streams the CSV to [sink] as two separate tables (L then R), each with
  /// its own header. Within each table, rows are sorted by
  /// `timestampSyncedMs`. The sink is not closed — the caller is responsible
  /// for flushing/closing it.
  static void writeToSink(StringSink sink, List<BufferedSample> samples) {
    final left = samples.where((s) => s.wheel == WheelSide.left).toList()
      ..sort((a, b) => a.timestampSyncedMs.compareTo(b.timestampSyncedMs));
    final right = samples.where((s) => s.wheel == WheelSide.right).toList()
      ..sort((a, b) => a.timestampSyncedMs.compareTo(b.timestampSyncedMs));

    _writeWheelSection(sink, 'L', left);
    sink.writeln(); // blank line separator between tables
    _writeWheelSection(sink, 'R', right);
  }

  static void _writeWheelSection(
    StringSink sink,
    String label,
    List<BufferedSample> samples,
  ) {
    sink.writeln('$commentPrefix Wheel: $label');
    sink.writeln(header);
    for (final s in samples) {
      sink.writeln(_formatRow(s));
    }
  }

  static String _formatRow(BufferedSample s) {
    final wheel = s.wheel == WheelSide.left ? 'L' : 'R';
    final marker = s.marker ? '1' : '0';
    return [
      s.reading.seq.toString(),
      wheel,
      s.timestampAppMs.toString(),
      _fmtDouble(s.timestampSyncedMs),
      _fmtDouble(s.reading.ax),
      _fmtDouble(s.reading.ay),
      _fmtDouble(s.reading.az),
      _fmtDouble(s.reading.gx),
      _fmtDouble(s.reading.gy),
      _fmtDouble(s.reading.gz),
      marker,
    ].join(',');
  }

  /// Formats a double without unnecessary trailing zeros.
  /// `1.0` → `1`, `1.50` → `1.5`, `0.0` → `0`, `-2.3` → `-2.3`.
  static String _fmtDouble(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    // Strip trailing zeros from the decimal representation.
    var s = v.toStringAsFixed(6);
    // Remove trailing zeros and possible trailing dot.
    s = s.replaceAll(RegExp(r'0+$'), '');
    s = s.replaceAll(RegExp(r'\.$'), '');
    return s;
  }
}
