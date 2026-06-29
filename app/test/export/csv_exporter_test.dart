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
      final firstLine = csv.split('\n').first;
      expect(
        firstLine,
        'seq,wheel,timestamp_app_ms,timestamp_device_us,'
        'timestamp_synced_ms,ax,ay,az,gx,gy,gz,marker',
      );
    });

    test('empty samples produces header only', () {
      final csv = CsvExporter.toCsvString(const []);
      final lines = csv.trim().split('\n');
      expect(lines.length, 1);
      expect(lines.first, startsWith('seq,'));
    });

    test('single sample produces correct row', () {
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
      expect(lines.length, 2);
      expect(lines[1], '42,L,2000,1000000,1000.5,1,2,3,4,5,6,0');
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
      final lines = csv.trim().split('\n');
      expect(lines[1].endsWith(',1'), isTrue);
    });

    test('wheel column is L or R', () {
      final samples = [
        _sample(seq: 0, tDeviceUs: 0, syncedMs: 0, wheel: WheelSide.left),
        _sample(seq: 1, tDeviceUs: 0, syncedMs: 0, wheel: WheelSide.right),
      ];
      final csv = CsvExporter.toCsvString(samples);
      final lines = csv.trim().split('\n');
      expect(lines[1].split(',')[1], 'L');
      expect(lines[2].split(',')[1], 'R');
    });

    test('samples sorted by timestamp_synced_ms', () {
      final samples = [
        _sample(seq: 3, tDeviceUs: 3000, syncedMs: 3000, wheel: WheelSide.left),
        _sample(seq: 1, tDeviceUs: 1000, syncedMs: 1000, wheel: WheelSide.left),
        _sample(seq: 2, tDeviceUs: 2000, syncedMs: 2000, wheel: WheelSide.right),
      ];
      final csv = CsvExporter.toCsvString(samples);
      final lines = csv.trim().split('\n');
      // seq should be 1, 2, 3 after sorting by synced_ms
      expect(lines[1].split(',')[0], '1');
      expect(lines[2].split(',')[0], '2');
      expect(lines[3].split(',')[0], '3');
    });

    test('L and R interleaved by synced_ms', () {
      final samples = [
        _sample(seq: 10, tDeviceUs: 100, syncedMs: 100, wheel: WheelSide.right),
        _sample(seq: 5, tDeviceUs: 50, syncedMs: 50, wheel: WheelSide.left),
        _sample(seq: 20, tDeviceUs: 200, syncedMs: 200, wheel: WheelSide.right),
        _sample(seq: 10, tDeviceUs: 100, syncedMs: 100, wheel: WheelSide.left),
      ];
      final csv = CsvExporter.toCsvString(samples);
      final lines = csv.trim().split('\n');
      // After sorting: 50(L), 100(L), 100(R), 200(R)
      expect(lines[1].split(',')[1], 'L'); // synced=50
      expect(lines[2].split(',')[1], 'L'); // synced=100 (L comes first)
      expect(lines[3].split(',')[1], 'R'); // synced=100 (R)
      expect(lines[4].split(',')[1], 'R'); // synced=200
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
      final line = csv.trim().split('\n')[1];
      final fields = line.split(',');
      expect(fields[5], '1.5'); // ax
      expect(fields[6], '0'); // ay
      expect(fields[7], '-2.3'); // az
    });

    test('streaming export via sink (for large files)', () {
      final sink = StringBuffer();
      CsvExporter.writeToSink(sink, [
        _sample(seq: 0, tDeviceUs: 0, syncedMs: 0, wheel: WheelSide.left),
        _sample(seq: 1, tDeviceUs: 1000, syncedMs: 1, wheel: WheelSide.right),
      ]);
      final csv = sink.toString();
      final lines = csv.trim().split('\n');
      expect(lines.length, 3); // header + 2 rows
      expect(lines[0], startsWith('seq,'));
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
      final line = csv.trim().split('\n')[1];
      expect(line.split(',')[4], '-100.5');
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
      final line = csv.trim().split('\n')[1];
      expect(line.split(',')[0], '4294967295');
      expect(line.split(',')[3], '4294967295');
    });
  });
}
