import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/state/sync_engine.dart';

void main() {
  test('uint32 device clock unwraps across micros rollover', () {
    final clock = Uint32Unwrapper();
    expect(clock.unwrap(0xFFFFFFF0), 0xFFFFFFF0);
    expect(clock.unwrap(0x00000010), 0x100000010);
    expect(clock.unwrap(0x00000020), 0x100000020);
  });

  test('late device event does not move unwrap cursor backwards', () {
    final clock = Uint32Unwrapper();
    expect(clock.unwrap(100), 100);
    expect(clock.unwrap(200), 200);
    expect(clock.unwrap(150), 150);
    expect(clock.unwrap(210), 210);
  });

  test('clock fit uses lowest RTT half like the PC acquisition service', () {
    final fit = DriftFit.fit(const [
      SyncPoint(tDeviceUs: 0, tAppUs: 1000, rttUs: 100),
      SyncPoint(tDeviceUs: 1000, tAppUs: 2000, rttUs: 120),
      SyncPoint(tDeviceUs: 2000, tAppUs: 900000, rttUs: 10000),
      SyncPoint(tDeviceUs: 3000, tAppUs: -400000, rttUs: 12000),
    ]);

    expect(fit.slope, closeTo(1.0, 1e-12));
    expect(fit.interceptUs, closeTo(1000, 1e-9));
    expect(fit.bestRttUs, 100);
    expect(fit.medianRttUs, 5060);
    expect(fit.n, 4);
    expect(fit.fitPointCount, 2);
  });

  test('clock model maps phone monotonic time back to device micros', () {
    const fit = DriftFit(
      slope: 1.0002,
      interceptUs: 5000,
      residualRmsMs: 0,
      n: 10,
      fitPointCount: 5,
      bestRttUs: 1000,
      medianRttUs: 1500,
    );
    const deviceUs = 1234567;
    final phoneUs = fit.toSyncedUs(deviceUs);
    expect(fit.toDeviceUs(phoneUs), closeTo(deviceUs, 1));
  });

  test('sync observation uses round trip midpoint', () {
    final observation = SyncObservation.fromRoundTrip(
      t1AppUs: 1000,
      t2DeviceUs: 9000,
      t3AppUs: 5000,
    );
    expect(observation.rttUs, 4000);
    expect(observation.point.tAppUs, 3000);
    expect(observation.point.tDeviceUs, 9000);
    expect(observation.offset.offsetUs, 6000);
  });
}
