import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/ble/imu_packet.dart';
import 'package:wheelathlete/theme/theme.dart';
import 'package:wheelathlete/widgets/imu_chart.dart';

ImuReading _r(int seq, int tUs, {double ax = 0}) => ImuReading(
      seq: seq,
      tDeviceUs: tUs,
      ax: ax,
      ay: 0,
      az: 0,
      gx: 0,
      gy: 0,
      gz: 0,
    );

void main() {
  group('ImuChartBuffer.cap', () {
    test('keeps the last N readings when over the cap', () {
      final readings = [
        for (var i = 0; i < 10; i++) _r(i, i * 1000),
      ];
      final capped = ImuChartBuffer.cap(readings, 5);
      expect(capped.length, 5);
      expect(capped.first.seq, 5);
      expect(capped.last.seq, 9);
    });

    test('returns all readings when under the cap', () {
      final readings = [_r(0, 0), _r(1, 1000)];
      final capped = ImuChartBuffer.cap(readings, 5);
      expect(capped.length, 2);
    });

    test('empty input returns empty', () {
      expect(ImuChartBuffer.cap(const [], 5), isEmpty);
    });
  });

  group('ImuChartBuffer.trimToWindowMs', () {
    test('keeps only readings within the window of the latest', () {
      // tDeviceUs in microseconds: 0, 1s, 2s, 3s, 4s, 10s.
      final readings = [
        _r(0, 0),
        _r(1, 1000000),
        _r(2, 2000000),
        _r(3, 3000000),
        _r(4, 4000000),
        _r(5, 10000000),
      ];
      // 5s window = 5_000_000 us. Latest is at 10s; keep readings with t >= 5s.
      final trimmed = ImuChartBuffer.trimToWindowMs(readings, 5000000);
      expect(trimmed.length, 1);
      expect(trimmed.first.seq, 5);
    });

    test('keeps all readings when all within the window', () {
      final readings = [
        _r(0, 0),
        _r(1, 1000000),
        _r(2, 2000000),
      ];
      final trimmed = ImuChartBuffer.trimToWindowMs(readings, 5000000);
      expect(trimmed.length, 3);
    });

    test('empty input returns empty', () {
      expect(ImuChartBuffer.trimToWindowMs(const [], 5000000), isEmpty);
    });
  });

  group('ImuChartBuffer.decimate', () {
    test('returns input when under targetPoints', () {
      final readings = [_r(0, 0), _r(1, 1000), _r(2, 2000)];
      final out = ImuChartBuffer.decimate(readings, 10);
      expect(out.length, 3);
    });

    test('reduces to roughly targetPoints by even stride', () {
      final readings = [
        for (var i = 0; i < 100; i++) _r(i, i * 10000, ax: i.toDouble()),
      ];
      final out = ImuChartBuffer.decimate(readings, 25);
      expect(out.length, lessThanOrEqualTo(25));
      expect(out.length, greaterThanOrEqualTo(20));
      // First + last preserved.
      expect(out.first.seq, 0);
      expect(out.last.seq, 99);
    });

    test('always includes the last reading', () {
      final readings = [
        for (var i = 0; i < 50; i++) _r(i, i * 1000),
      ];
      final out = ImuChartBuffer.decimate(readings, 10);
      expect(out.last.seq, 49);
    });

    test('empty input returns empty', () {
      expect(ImuChartBuffer.decimate(const [], 10), isEmpty);
    });
  });

  group('ImuChartBuffer.toAccelSpots', () {
    test('maps readings to FlSpot(x=relativeMs, y=ax)', () {
      final readings = [
        _r(0, 0, ax: 1),
        _r(1, 10000, ax: 2), // 10ms later
      ];
      final spots = ImuChartBuffer.toAccelSpots(readings);
      expect(spots.length, 2);
      expect(spots.first.x, 0);
      expect(spots.first.y, 1);
      expect(spots.last.x, 10);
      expect(spots.last.y, 2);
    });
  });

  group('ImuChartBuffer.toGyroSpots', () {
    test('maps readings to FlSpot(x=relativeMs, y=gx)', () {
      final readings = [
        _r(0, 0),
        _r(1, 20000),
      ];
      // Override gyroscope via a custom reading.
      final r = [
        const ImuReading(
            seq: 0, tDeviceUs: 0, ax: 0, ay: 0, az: 0, gx: 5, gy: 0, gz: 0),
        const ImuReading(
            seq: 1, tDeviceUs: 20000, ax: 0, ay: 0, az: 0, gx: 7, gy: 0, gz: 0),
      ];
      final spots = ImuChartBuffer.toGyroSpots(r);
      expect(spots.length, 2);
      expect(spots.first.y, 5);
      expect(spots.last.x, 20);
      expect(spots.last.y, 7);
      // Suppress unused-var warning for readings.
      expect(readings.length, 2);
    });
  });

  group('ImuChart widget', () {
    testWidgets('renders with mock data without pumpAndSettle timeout',
        (tester) async {
      final readings = [
        for (var i = 0; i < 60; i++)
          ImuReading(
            seq: i,
            tDeviceUs: i * 10000,
            ax: (i % 10).toDouble(),
            ay: ((i + 1) % 10).toDouble(),
            az: ((i + 2) % 10).toDouble(),
            gx: (i % 5).toDouble(),
            gy: ((i + 1) % 5).toDouble(),
            gz: ((i + 2) % 5).toDouble(),
          ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: ImuChart(
              readings: readings,
              isAccel: true,
              axisColors: const [
                Color(0xFF2563EB),
                Color(0xFF16A34A),
                Color(0xFFEAB308),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // The chart widget tree should contain a LineChart.
      expect(find.byType(ImuChart), findsOneWidget);
      // No exception thrown → renders with mock data.
    });

    testWidgets('renders gyro chart with empty readings without crashing',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: ImuChart(
              readings: [],
              isAccel: false,
              axisColors: [
                Color(0xFF2563EB),
                Color(0xFF16A34A),
                Color(0xFFEAB308),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ImuChart), findsOneWidget);
    });
  });
}
