import 'package:wheelathlete/records/session_model.dart';
import 'package:wheelathlete/theme/theme.dart';

const analysisMaximumGapSeconds = .050;
const _uint32 = 0x100000000;
const _half32 = 0x80000000;

class TimedAnalysisReading {
  const TimedAnalysisReading(this.timeS, this.sample, this.sequence);
  final double timeS;
  double get tSeconds => timeS;
  final BufferedSample sample;
  final int sequence;
}

class AnalysisWheelTimeline {
  AnalysisWheelTimeline(this.readings, this.diagnostics);
  final List<TimedAnalysisReading> readings;
  final Map<String, dynamic> diagnostics;
}

AnalysisWheelTimeline prepareAnalysisWheel(
  List<BufferedSample> samples,
  WheelSide side,
  int sourceRateHz, {
  int? utcStartMs,
}) {
  if (sourceRateHz < 20 || sourceRateHz > 1000) {
    throw const FormatException('Source rate must be between 20 and 1000 Hz');
  }
  final selected = samples.where((s) => s.wheel == side).toList();
  if (selected.length < 2) {
    throw const FormatException(
      'Trajectory inference requires both left and right wheel recordings.',
    );
  }
  final unique = <int, BufferedSample>{};
  var anchorRaw = selected.first.reading.seq, anchor = 0;
  var duplicates = 0, reordered = 0, rollovers = 0;
  for (final sample in selected) {
    final r = sample.reading;
    if (r.seq < 0 ||
        r.seq >= _uint32 ||
        r.tDeviceUs < 0 ||
        r.tDeviceUs >= _uint32) {
      throw const FormatException('Invalid uint32 sample counter');
    }
    if (![
      sample.timestampSyncedMs,
      r.ax,
      r.ay,
      r.az,
      r.gx,
      r.gy,
      r.gz,
    ].every((v) => v.isFinite)) {
      throw const FormatException('Non-finite saved timestamps or IMU values');
    }
    final d = (r.seq - anchorRaw + _half32) % _uint32 - _half32;
    if (d == -_half32) throw const FormatException('Ambiguous sequence epoch');
    final position = anchor + d;
    final old = unique[position];
    if (old != null) {
      final a = old.reading;
      if (a.tDeviceUs != r.tDeviceUs ||
          a.ax != r.ax ||
          a.ay != r.ay ||
          a.az != r.az ||
          a.gx != r.gx ||
          a.gy != r.gy ||
          a.gz != r.gz) {
        throw const FormatException(
          'Conflicting duplicate sequence or device reset',
        );
      }
      duplicates++;
      continue;
    }
    unique[position] = sample;
    if (d > 0) {
      if (r.seq < anchorRaw) rollovers++;
      anchor = position;
      anchorRaw = r.seq;
    } else if (d < 0) {
      reordered++;
    }
  }
  final keys = unique.keys.toList()..sort();
  if (keys.length < 2 || keys.last - keys.first >= _half32) {
    throw const FormatException('Ambiguous sequence span');
  }
  final ordered = keys.map((k) => unique[k]!).toList();
  final allSameTime = ordered.every(
    (s) => s.timestampSyncedMs == ordered.first.timestampSyncedMs,
  );
  final usesUtc = ordered.first.timestampSyncedMs >= 100000000000;
  if (ordered.any((s) => (s.timestampSyncedMs >= 100000000000) != usesUtc)) {
    throw const FormatException('Mixed UTC and recording-relative timestamps');
  }
  final times = <double>[];
  var basis = allSameTime
      ? 'legacy_sequence_saved_anchor'
      : 'saved_start_relative';
  for (var i = 0; i < ordered.length; i++) {
    var ms = ordered[i].timestampSyncedMs;
    if (ms >= 100000000000) {
      if (utcStartMs == null) {
        throw const FormatException(
          'Legacy UTC timestamps need the saved UTC start',
        );
      }
      ms -= utcStartMs;
      basis = allSameTime
          ? 'legacy_utc_sequence_saved_anchor'
          : 'legacy_utc_start_relative';
    }
    final t = allSameTime
        ? ms / 1000 + (keys[i] - keys.first) / sourceRateHz
        : ms / 1000;
    if (i > 0 && t <= times.last) {
      throw const FormatException(
        'Saved timeline is nonmonotonic; no silent timestamp repair',
      );
    }
    times.add(t);
  }
  var missing = 0;
  for (var i = 1; i < keys.length; i++) {
    final sequenceHole = keys[i] - keys[i - 1] - 1;
    missing += sequenceHole;
    if (sequenceHole / sourceRateHz > analysisMaximumGapSeconds + 1e-9) {
      throw const FormatException(
        'Sequence gap exceeds 0.05 s; analysis refused',
      );
    }
    final d =
        (ordered[i].reading.tDeviceUs - ordered[i - 1].reading.tDeviceUs) %
        _uint32;
    if (d == 0 || d >= _half32) {
      throw const FormatException('Device clock reset or duplicate timestamp');
    }
    if (times[i] - times[i - 1] > analysisMaximumGapSeconds + 1e-9 ||
        d / 1e6 > analysisMaximumGapSeconds + 1e-9) {
      throw const FormatException(
        'Recording gap exceeds 0.05 s; analysis refused, raw data preserved',
      );
    }
  }
  return AnalysisWheelTimeline(
    List.unmodifiable(
      List.generate(
        keys.length,
        (i) => TimedAnalysisReading(times[i], ordered[i], keys[i]),
      ),
    ),
    {
      'time_basis': basis,
      'source_samples': selected.length,
      'unique_samples': keys.length,
      'duplicates': duplicates,
      'reordered': reordered,
      'rollovers': rollovers,
      'missing_sequences': missing,
    },
  );
}
