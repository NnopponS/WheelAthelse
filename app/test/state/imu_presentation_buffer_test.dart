import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/ble/imu_packet.dart';
import 'package:wheelathlete/state/imu_providers.dart';
import 'package:wheelathlete/state/imu_presentation_buffer.dart';

ImuReading _reading(int seq) => ImuReading(
  seq: seq,
  tDeviceUs: seq * 5000,
  ax: seq.toDouble(),
  ay: 0,
  az: 1,
  gx: 0,
  gy: 0,
  gz: 0,
);

void main() {
  test('production live presentation refreshes at approximately 30 Hz', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      container.read(imuEmitIntervalProvider),
      const Duration(milliseconds: 33),
    );
  });

  test('sustained input keeps only the newest fixed-capacity chart window', () {
    final buffer = ImuPresentationBuffer(capacity: 300);

    for (var seq = 0; seq < 4000; seq++) {
      buffer.add(_reading(seq), dropCount: 7);
    }

    final snapshot = buffer.snapshot();
    expect(snapshot.sampleCount, 4000);
    expect(snapshot.dropCount, 7);
    expect(snapshot.latest?.seq, 3999);
    expect(snapshot.recent, hasLength(300));
    expect(snapshot.recent.first.seq, 3700);
    expect(snapshot.recent.last.seq, 3999);
  });

  test('snapshot is defensive and reset starts a clean acquisition', () {
    final buffer = ImuPresentationBuffer(capacity: 3)
      ..add(_reading(1), dropCount: 0)
      ..add(_reading(2), dropCount: 1);

    final beforeReset = buffer.snapshot();
    buffer
      ..reset()
      ..add(_reading(10), dropCount: 0);

    expect(beforeReset.recent.map((sample) => sample.seq), [1, 2]);
    expect(buffer.snapshot().recent.map((sample) => sample.seq), [10]);
    expect(buffer.snapshot().sampleCount, 1);
  });
}
