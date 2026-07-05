import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/ble/imu_packet.dart';
import 'package:wheelathlete/export/csv_exporter.dart';
import 'package:wheelathlete/records/session_model.dart';
import 'package:wheelathlete/theme/theme.dart';

BufferedSample _sample({
  required int seq,
  required int tDeviceUs,
  required double syncedMs,
  required WheelSide wheel,
  double ax = 1.0,
  double ay = 0,
  double az = 0,
  double gx = 0,
  double gy = 0,
  double gz = 0,
  int timestampAppMs = 0,
  bool marker = false,
}) =>
    BufferedSample(
      reading: ImuReading(
        seq: seq,
        tDeviceUs: tDeviceUs,
        ax: ax,
        ay: ay,
        az: az,
        gx: gx,
        gy: gy,
        gz: gz,
      ),
      wheel: wheel,
      timestampAppMs: timestampAppMs,
      timestampSyncedMs: syncedMs,
      marker: marker,
    );

void main() {
  group('CsvExporter', () {
    test('header matches schema (§3)', () {
      final csv = CsvExporter.toCsvString(const []);
      final lines = csv.split('\n');
      // First line is the L section comment, second is the header.
      expect(lines[0], '# Wheel: L');
      expect(
        lines[1],
        'seq,wheel,timestamp_app_ms,timestamp_utc_ms,'
        'ax,ay,az,gx,gy,gz,marker',
      );
    });

    test('empty samples produces L and R section headers only', () {
      final csv = CsvExporter.toCsvString(const []);
      final lines = csv.trim().split('\n');
      // # Wheel: L, header, (empty), # Wheel: R, header
      expect(lines[0], '# Wheel: L');
      expect(lines[1], startsWith('seq,'));
      expect(lines[2], ''); // blank line separator
      expect(lines[3], '# Wheel: R');
      expect(lines[4], startsWith('seq,'));
    });

    test('single L sample produces correct row in L table', () {
      final samples = [
        _sample(
          seq: 42,
          tDeviceUs: 1000000,
          syncedMs: 1000.5,
          wheel: WheelSide.left,
          ax: 1.0,
          ay: 2.0,
          az: 3.0,
          gx: 4.0,
          gy: 5.0,
          gz: 6.0,
          timestampAppMs: 2000,
        ),
      ];
      final csv = CsvExporter.toCsvString(samples);
      final lines = csv.trim().split('\n');
      // # Wheel: L, header, data, (empty), # Wheel: R, header
      expect(lines[0], '# Wheel: L');
      expect(lines[1], startsWith('seq,'));
      expect(lines[2], '42,L,2000,1000.5,1,2,3,4,5,6,0');
      expect(lines[3], ''); // blank line separator
      expect(lines[4], '# Wheel: R');
      expect(lines[5], startsWith('seq,'));
    });

    test('marker flag is 1 when marker=true', () {
      final samples = [
        _sample(
          seq: 0,
          tDeviceUs: 0,
          syncedMs: 0,
          wheel: WheelSide.left,
          marker: true,
        ),
      ];
      final csv = CsvExporter.toCsvString(samples);
      final dataLines = csv.trim().split('\n').where((l) {
        final t = l.trim();
        return !t.startsWith('#') && !t.startsWith('seq,') && t.isNotEmpty;
      }).toList();
      expect(dataLines.first.endsWith(',1'), isTrue);
    });

    test('wheel column is L or R in separate tables', () {
      final samples = [
        _sample(seq: 0, tDeviceUs: 0, syncedMs: 0, wheel: WheelSide.left),
        _sample(seq: 1, tDeviceUs: 0, syncedMs: 0, wheel: WheelSide.right),
      ];
      final csv = CsvExporter.toCsvString(samples);
      final lines = csv.trim().split('\n');
      // L table: comment, header, 0,L
      // blank
      // R table: comment, header, 1,R
      expect(lines[0], '# Wheel: L');
      expect(lines[1], startsWith('seq,'));
      expect(lines[2].split(',')[1], 'L');
      expect(lines[3], ''); // blank line separator
      expect(lines[4], '# Wheel: R');
      expect(lines[5], startsWith('seq,'));
      expect(lines[6].split(',')[1], 'R');
    });

    test('L and R samples are in separate tables, each sorted by synced_ms',
        () {
      final samples = [
        _sample(seq: 10, tDeviceUs: 100, syncedMs: 100, wheel: WheelSide.right),
        _sample(seq: 5, tDeviceUs: 50, syncedMs: 50, wheel: WheelSide.left),
        _sample(seq: 20, tDeviceUs: 200, syncedMs: 200, wheel: WheelSide.right),
        _sample(seq: 10, tDeviceUs: 100, syncedMs: 100, wheel: WheelSide.left),
      ];
      final csv = CsvExporter.toCsvString(samples);
      final lines = csv.trim().split('\n');
      // L table: # Wheel: L, header, 5(L@50), 10(L@100)
      // blank
      // R table: # Wheel: R, header, 10(R@100), 20(R@200)
      expect(lines[0], '# Wheel: L');
      expect(lines[2].split(',')[0], '5'); // L synced=50
      expect(lines[3].split(',')[0], '10'); // L synced=100
      expect(lines[4], ''); // blank line separator
      expect(lines[5], '# Wheel: R');
      expect(lines[7].split(',')[0], '10'); // R synced=100
      expect(lines[8].split(',')[0], '20'); // R synced=200
    });

    test('double values formatted without trailing zeros', () {
      final samples = [
        _sample(
          seq: 0,
          tDeviceUs: 0,
          syncedMs: 0,
          wheel: WheelSide.left,
          ax: 1.50,
          ay: 0.0,
          az: -2.3,
        ),
      ];
      final csv = CsvExporter.toCsvString(samples);
      final dataLines = csv.trim().split('\n').where((l) {
        final t = l.trim();
        return !t.startsWith('#') && !t.startsWith('seq,') && t.isNotEmpty;
      }).toList();
      final fields = dataLines.first.split(',');
      expect(fields[4], '1.5'); // ax
      expect(fields[5], '0'); // ay
      expect(fields[6], '-2.3'); // az
    });

    test('streaming export via sink (for large files)', () {
      final sink = StringBuffer();
      CsvExporter.writeToSink(sink, [
        _sample(seq: 0, tDeviceUs: 0, syncedMs: 0, wheel: WheelSide.left),
        _sample(seq: 1, tDeviceUs: 1000, syncedMs: 1, wheel: WheelSide.right),
      ]);
      final csv = sink.toString();
      final lines = csv.trim().split('\n');
      // L table: comment, header, 1 row
      // blank
      // R table: comment, header, 1 row
      expect(lines[0], '# Wheel: L');
      expect(lines[1], startsWith('seq,'));
      expect(lines[2].split(',')[1], 'L');
      expect(lines[3], ''); // blank line separator
      expect(lines[4], '# Wheel: R');
      expect(lines[5], startsWith('seq,'));
      expect(lines[6].split(',')[1], 'R');
    });

    test('handles negative synced timestamps', () {
      final samples = [
        _sample(
          seq: 0,
          tDeviceUs: 0,
          syncedMs: -100.5,
          wheel: WheelSide.left,
        ),
      ];
      final csv = CsvExporter.toCsvString(samples);
      final dataLines = csv.trim().split('\n').where((l) {
        final t = l.trim();
        return !t.startsWith('#') && !t.startsWith('seq,') && t.isNotEmpty;
      }).toList();
      expect(dataLines.first.split(',')[3], '-100.5');
    });

    test('handles large seq numbers (uint32 max)', () {
      final samples = [
        _sample(
          seq: 4294967295,
          tDeviceUs: 4294967295,
          syncedMs: 0,
          wheel: WheelSide.left,
        ),
      ];
      final csv = CsvExporter.toCsvString(samples);
      final dataLines = csv.trim().split('\n').where((l) {
        final t = l.trim();
        return !t.startsWith('#') && !t.startsWith('seq,') && t.isNotEmpty;
      }).toList();
      final fields = dataLines.first.split(',');
      // seq handles uint32 max. The raw on-device microsecond timestamp is
      // no longer exported (replaced by timestamp_utc_ms — see issue #4).
      expect(fields[0], '4294967295');
    });

    test('does not export the raw device timestamp column', () {
      final samples = [
        _sample(seq: 0, tDeviceUs: 123456789, syncedMs: 42, wheel: WheelSide.left),
      ];
      final csv = CsvExporter.toCsvString(samples);
      final lines = csv.trim().split('\n');
      expect(lines[1], isNot(contains('timestamp_device_us')));
      expect(lines[1], contains('timestamp_utc_ms'));
      // Data row: seq,wheel,timestamp_app_ms,timestamp_utc_ms,ax..gz,marker
      // (11 fields — no device-us column).
      expect(lines[2].split(',').length, 11);
      // 123456789 (the raw device us value) must not appear anywhere in the
      // row — only the UTC ms value (42) should be present.
      expect(lines[2], isNot(contains('123456789')));
    });

    test('L table always comes before R table', () {
      final samples = [
        _sample(seq: 0, tDeviceUs: 0, syncedMs: 0, wheel: WheelSide.right),
        _sample(seq: 1, tDeviceUs: 0, syncedMs: 0, wheel: WheelSide.left),
      ];
      final csv = CsvExporter.toCsvString(samples);
      final lIdx = csv.indexOf('# Wheel: L');
      final rIdx = csv.indexOf('# Wheel: R');
      expect(lIdx, lessThan(rIdx));
    });

    test('blank line separates L and R tables', () {
      final samples = [
        _sample(seq: 0, tDeviceUs: 0, syncedMs: 0, wheel: WheelSide.left),
        _sample(seq: 1, tDeviceUs: 0, syncedMs: 0, wheel: WheelSide.right),
      ];
      final csv = CsvExporter.toCsvString(samples);
      // After L data row, there should be a blank line before # Wheel: R
      final lines = csv.split('\n');
      final lDataIdx = lines.indexWhere((l) => l.startsWith('0,L'));
      final rCommentIdx = lines.indexWhere((l) => l.trim() == '# Wheel: R');
      // The line between L data and R comment should be empty
      expect(lines[lDataIdx + 1].trim(), isEmpty);
      expect(rCommentIdx, lDataIdx + 2);
    });
  });
}
