import 'package:wheelathlete/ble/imu_packet.dart';
import 'package:wheelathlete/export/csv_exporter.dart';
import 'package:wheelathlete/records/session_model.dart';
import 'package:wheelathlete/theme/theme.dart';

/// Pure parser for the CSV format written by [CsvExporter] (architecture.md
/// §3): two separate per-wheel tables (`# Wheel: L` then `# Wheel: R`), each
/// with its own `seq,...` header, one row per sample.
///
/// This is the single source of truth for reading session CSVs back into
/// [BufferedSample]s. Both [StorageRepository] implementations
/// (`PathProviderStorageRepository` for real files and
/// `InMemoryStorageRepository` for tests) route through this class, so the
/// exact parsing logic exercised on real files on-device is also exercised
/// by the test suite — a real file's CSV round-trip bug would previously go
/// undetected because the in-memory test double bypassed CSV serialization
/// entirely.
///
/// Because L and R are stored as two separate tables (not interleaved), a
/// "row index into the file" is not the same as "index into the
/// chronologically-merged, both-wheels stream" that callers like the
/// preview page's scrubber expect (`sampleCount` counts both wheels
/// combined). [parse] merges the two tables back into a single list ordered
/// by `timestamp_utc_ms` (ties broken with L before R, matching the legacy
/// single-table format) so callers can treat the result as one flat,
/// chronological timeline regardless of how it's stored on disk.
class CsvSampleParser {
  const CsvSampleParser._();

  /// Parses the full CSV [content] into a chronologically-merged list of
  /// [BufferedSample]s (both wheels combined, sorted by
  /// `timestamp_utc_ms`, L before R on exact ties).
  ///
  /// Skips blank lines, `#` section comments, and `seq,` headers. Malformed
  /// rows (too few fields) are skipped rather than throwing, so a single
  /// corrupt line doesn't take down the whole session.
  static List<BufferedSample> parse(String content) {
    final left = <BufferedSample>[];
    final right = <BufferedSample>[];
    for (final line in content.split('\n')) {
      final sample = parseLine(line);
      if (sample == null) continue;
      (sample.wheel == WheelSide.left ? left : right).add(sample);
    }
    left.sort((a, b) => a.timestampSyncedMs.compareTo(b.timestampSyncedMs));
    right.sort((a, b) => a.timestampSyncedMs.compareTo(b.timestampSyncedMs));
    return _mergeByTime(left, right);
  }

  /// Parses one CSV data line into a [BufferedSample], or null if the line
  /// is blank, a comment, a header, or malformed.
  ///
  /// Public so [StorageRepository.readSampleChunk] can parse a streaming
  /// line-at-a-time view of the file without loading the whole thing.
  static BufferedSample? parseLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith(CsvExporter.commentPrefix)) return null;
    if (trimmed.startsWith('seq,')) return null;
    final f = trimmed.split(',');
    // seq,wheel,timestamp_app_ms,timestamp_utc_ms,ax,ay,az,gx,gy,gz,marker
    if (f.length < 11) return null;
    try {
      final utcMs = double.parse(f[3]);
      return BufferedSample(
        reading: ImuReading(
          seq: int.parse(f[0]),
          // The raw on-device microsecond counter is no longer persisted
          // (issue #4) — reconstruct a monotonic-per-wheel synthetic value
          // from the UTC ms column so relative-time chart math (e.g.
          // ImuChart, which only ever computes *differences* between
          // readings of the same wheel) keeps working after a reload.
          tDeviceUs: (utcMs * 1000).round(),
          ax: double.parse(f[4]),
          ay: double.parse(f[5]),
          az: double.parse(f[6]),
          gx: double.parse(f[7]),
          gy: double.parse(f[8]),
          gz: double.parse(f[9]),
        ),
        wheel: f[1] == 'L' ? WheelSide.left : WheelSide.right,
        timestampAppMs: int.parse(f[2]),
        timestampSyncedMs: utcMs,
        marker: f[10] == '1',
      );
    } on FormatException {
      return null;
    }
  }

  /// Stable 2-way merge of two lists (each already sorted ascending by
  /// `timestampSyncedMs`) into one chronological list. On an exact tie, the
  /// element from [left] comes first — matching the tie-break rule of the
  /// legacy single-table CSV format.
  static List<BufferedSample> _mergeByTime(
    List<BufferedSample> left,
    List<BufferedSample> right,
  ) {
    final merged = <BufferedSample>[];
    var i = 0, j = 0;
    while (i < left.length && j < right.length) {
      if (left[i].timestampSyncedMs <= right[j].timestampSyncedMs) {
        merged.add(left[i++]);
      } else {
        merged.add(right[j++]);
      }
    }
    merged.addAll(left.skip(i));
    merged.addAll(right.skip(j));
    return merged;
  }
}
