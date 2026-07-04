import 'package:wheelathlete/records/session_model.dart';
import 'package:wheelathlete/theme/theme.dart';

/// CSV exporter for WheelAthlete session data (architecture.md §3).
///
/// Schema (two separate tables — one per wheel):
/// ```
/// # Wheel: L
/// seq,wheel,timestamp_app_ms,timestamp_device_us,timestamp_synced_ms,
/// ax,ay,az,gx,gy,gz,marker
/// 0,L,...
/// 1,L,...
///
/// # Wheel: R
/// seq,wheel,timestamp_app_ms,timestamp_device_us,timestamp_synced_ms,
/// ax,ay,az,gx,gy,gz,marker
/// 0,R,...
/// 1,R,...
/// ```
///
/// - L and R samples are written as **separate tables**, each with its own
///   header. Within each table, rows are sorted by `timestamp_synced_ms`.
/// - `wheel` column is `L` or `R`.
/// - `marker` is `1` when a Mark Event was active, `0` otherwise.
/// - Double values are formatted without unnecessary trailing zeros.
/// - Lines starting with `#` are section comments (skipped by parsers).
///
/// For large sessions, use [writeToSink] to stream to a file without building
/// the entire CSV string in memory.
class CsvExporter {
  const CsvExporter._();

  static const String header =
      'seq,wheel,timestamp_app_ms,timestamp_device_us,'
      'timestamp_synced_ms,ax,ay,az,gx,gy,gz,marker';

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
      s.reading.tDeviceUs.toString(),
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
