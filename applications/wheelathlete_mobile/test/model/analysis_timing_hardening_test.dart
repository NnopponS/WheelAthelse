import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/ble/imu_packet.dart';
import 'package:wheelathlete/model/analysis_timing.dart';
import 'package:wheelathlete/records/session_model.dart';
import 'package:wheelathlete/theme/theme.dart';

List<BufferedSample> readings({
  bool hiddenSequenceGap = false,
  bool utc = false,
  bool repeated = false,
}) {
  const start = 1700000000000;
  return List.generate(
    40,
    (index) => BufferedSample(
      reading: ImuReading(
        seq: index + (hiddenSequenceGap && index >= 20 ? 100 : 0),
        tDeviceUs: index * 10000,
        ax: 1.0,
        ay: 0.0,
        az: 0.0,
        gx: 0.0,
        gy: 0.0,
        gz: 0.0,
      ),
      wheel: WheelSide.left,
      timestampAppMs: index * 10,
      timestampSyncedMs: (utc ? start : 0.0) + (repeated ? 0.0 : index * 10),
    ),
  );
}

void main() {
  test('public timing helper rejects an invalid configured rate', () {
    expect(
      () => prepareAnalysisWheel(readings(), WheelSide.left, 0),
      throwsFormatException,
    );
    expect(
      () => prepareAnalysisWheel(readings(), WheelSide.left, 1001),
      throwsFormatException,
    );
  });
  test('large missing sequence span cannot hide behind smooth timestamps', () {
    expect(
      () => prepareAnalysisWheel(
        readings(hiddenSequenceGap: true),
        WheelSide.left,
        100,
      ),
      throwsFormatException,
    );
  });
  test(
    'mixed UTC and relative values are rejected before timeline construction',
    () {
      final samples = readings();
      samples[20] = samples[20].copyWith(timestampSyncedMs: 1700000000000);
      expect(
        () => prepareAnalysisWheel(
          samples,
          WheelSide.left,
          100,
          utcStartMs: 1700000000000,
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'repeated UTC clock retains explicit nominal-cadence fallback provenance',
    () {
      final result = prepareAnalysisWheel(
        readings(utc: true, repeated: true),
        WheelSide.left,
        100,
        utcStartMs: 1700000000000,
      );
      expect(
        result.diagnostics['time_basis'],
        'legacy_utc_sequence_saved_anchor',
      );
      expect(result.readings.first.timeS, 0.0);
      expect(result.readings.last.timeS, 0.39);
    },
  );
  test('normal UTC clock uses the saved common origin', () {
    final result = prepareAnalysisWheel(
      readings(utc: true),
      WheelSide.left,
      100,
      utcStartMs: 1700000000000,
    );
    expect(result.diagnostics['time_basis'], 'legacy_utc_start_relative');
    expect(result.readings.last.timeS, 0.39);
  });
}
