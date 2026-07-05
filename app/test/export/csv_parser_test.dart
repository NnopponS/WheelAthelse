import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/ble/imu_packet.dart';
import 'package:wheelathlete/export/csv_exporter.dart';
import 'package:wheelathlete/export/csv_parser.dart';
import 'package:wheelathlete/records/session_model.dart';
import 'package:wheelathlete/theme/theme.dart';

BufferedSample _sample({
  required int seq,
  required double syncedMs,
  required WheelSide wheel,
  double ax = 1.0,
  int timestampAppMs = 0,
  bool marker = false,
}) =>
    BufferedSample(
      reading: ImuReading(
        seq: seq,
        tDeviceUs: 0,
        ax: ax,
        ay: 0,
        az: 0,
        gx: 0,
        gy: 0,
        gz: 0,
      ),
      wheel: wheel,
      timestampAppMs: timestampAppMs,
      timestampSyncedMs: syncedMs,
      marker: marker,
    );

void main() {
  group('CsvSampleParser.parse', () {
    test('round-trips CsvExporter output back to the original samples', () {
      final samples = [
        _sample(seq: 0, syncedMs: 0, wheel: WheelSide.left, ax: 1),
        _sample(seq: 1, syncedMs: 10, wheel: WheelSide.left, ax: 2),
        _sample(seq: 0, syncedMs: 5, wheel: WheelSide.right, ax: 3),
        _sample(seq: 1, syncedMs: 15, wheel: WheelSide.right, ax: 4),
      ];
      final csv = CsvExporter.toCsvString(samples);
      final parsed = CsvSampleParser.parse(csv);

      expect(parsed.length, 4);
      // Chronologically merged across both wheels: L@0, R@5, L@10, R@15.
      expect(parsed.map((s) => s.timestampSyncedMs).toList(), [0, 5, 10, 15]);
      expect(parsed.map((s) => s.wheel).toList(), [
        WheelSide.left,
        WheelSide.right,
        WheelSide.left,
        WheelSide.right,
      ]);
      expect(parsed.map((s) => s.reading.ax).toList(), [1, 3, 2, 4]);
    });

    test('merges L and R tables in chronological order even though they '
        'are stored as separate blocks in the file', () {
      final samples = [
        _sample(seq: 10, syncedMs: 100, wheel: WheelSide.right),
        _sample(seq: 5, syncedMs: 50, wheel: WheelSide.left),
        _sample(seq: 20, syncedMs: 200, wheel: WheelSide.right),
        _sample(seq: 15, syncedMs: 150, wheel: WheelSide.left),
      ];
      final csv = CsvExporter.toCsvString(samples);
      final parsed = CsvSampleParser.parse(csv);

      expect(parsed.map((s) => s.timestampSyncedMs).toList(),
          [50, 100, 150, 200]);
    });

    test('breaks exact timestamp ties with L before R', () {
      final samples = [
        _sample(seq: 0, syncedMs: 10, wheel: WheelSide.right),
        _sample(seq: 0, syncedMs: 10, wheel: WheelSide.left),
      ];
      final csv = CsvExporter.toCsvString(samples);
      final parsed = CsvSampleParser.parse(csv);

      expect(parsed.length, 2);
      expect(parsed[0].wheel, WheelSide.left);
      expect(parsed[1].wheel, WheelSide.right);
    });

    test('skips comment lines and headers', () {
      const csv = '# Wheel: L\n'
          'seq,wheel,timestamp_app_ms,timestamp_utc_ms,ax,ay,az,gx,gy,gz,marker\n'
          '0,L,0,0,1,0,0,0,0,0,0\n'
          '\n'
          '# Wheel: R\n'
          'seq,wheel,timestamp_app_ms,timestamp_utc_ms,ax,ay,az,gx,gy,gz,marker\n';
      final parsed = CsvSampleParser.parse(csv);
      expect(parsed.length, 1);
      expect(parsed.first.reading.seq, 0);
    });

    test('empty content returns empty list', () {
      expect(CsvSampleParser.parse(''), isEmpty);
    });

    test('skips malformed rows without throwing', () {
      const csv = '# Wheel: L\n'
          'seq,wheel,timestamp_app_ms,timestamp_utc_ms,ax,ay,az,gx,gy,gz,marker\n'
          '0,L,0,0,1,0,0,0,0,0,0\n'
          'not,a,valid,row\n'
          '1,L,10,10,2,0,0,0,0,0,0\n';
      final parsed = CsvSampleParser.parse(csv);
      expect(parsed.length, 2);
      expect(parsed.map((s) => s.reading.seq).toList(), [0, 1]);
    });

    test('marker flag round-trips correctly', () {
      final samples = [
        _sample(seq: 0, syncedMs: 0, wheel: WheelSide.left, marker: true),
      ];
      final csv = CsvExporter.toCsvString(samples);
      final parsed = CsvSampleParser.parse(csv);
      expect(parsed.single.marker, isTrue);
    });

    test('reconstructs a monotonic tDeviceUs per wheel from timestamp_utc_ms '
        '(the raw device counter is not persisted)', () {
      final samples = [
        _sample(seq: 0, syncedMs: 0, wheel: WheelSide.left),
        _sample(seq: 1, syncedMs: 10, wheel: WheelSide.left),
      ];
      final csv = CsvExporter.toCsvString(samples);
      final parsed = CsvSampleParser.parse(csv);
      expect(parsed[1].reading.tDeviceUs, greaterThan(parsed[0].reading.tDeviceUs));
    });
  });
}
