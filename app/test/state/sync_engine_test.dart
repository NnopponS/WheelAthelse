import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/state/sync_engine.dart';

void main() {
  group('OffsetEstimate.compute (§4.2)', () {
    test('zero offset when device time = phone time + RTT/2', () {
      // T1 = 1000000 us, T2 = 1004000 us, T3 = 1008000 us
      // RTT = 8000 us, offset = T2 - (T1 + RTT/2) = 1004000 - (1000000 + 4000) = 0
      final est = OffsetEstimate.compute(
        t1AppUs: 1000000,
        t2DeviceUs: 1004000,
        t3AppUs: 1008000,
      );
      expect(est.rttMs, 8.0);
      expect(est.offsetUs, 0);
    });

    test('positive offset when device clock is ahead of phone', () {
      // Device clock is 5000 us (5 ms) ahead.
      // T1 = 1000000 us, T2 = 1009000 us, T3 = 1008000 us
      // offset = 1009000 - (1000000 + 4000) = 5000 us
      final est = OffsetEstimate.compute(
        t1AppUs: 1000000,
        t2DeviceUs: 1009000,
        t3AppUs: 1008000,
      );
      expect(est.rttMs, 8.0);
      expect(est.offsetUs, 5000);
    });

    test('negative offset when device clock is behind phone', () {
      // Device clock is 3000 us (3 ms) behind.
      // T1 = 1000000 us, T2 = 1001000 us, T3 = 1008000 us
      // offset = 1001000 - (1000000 + 4000) = -3000 us
      final est = OffsetEstimate.compute(
        t1AppUs: 1000000,
        t2DeviceUs: 1001000,
        t3AppUs: 1008000,
      );
      expect(est.rttMs, 8.0);
      expect(est.offsetUs, -3000);
    });

    test('RTT is always non-negative (T3 >= T1)', () {
      final est = OffsetEstimate.compute(
        t1AppUs: 1000000,
        t2DeviceUs: 1000000,
        t3AppUs: 1000000, // RTT = 0 (instant)
      );
      expect(est.rttMs, 0.0);
    });

    test('sub-ms precision: RTT of 8.5ms is preserved', () {
      // T1 = 1000000 us, T3 = 1008500 us → RTT = 8500 us = 8.5 ms
      final est = OffsetEstimate.compute(
        t1AppUs: 1000000,
        t2DeviceUs: 1004250,
        t3AppUs: 1008500,
      );
      expect(est.rttMs, 8.5);
      expect(est.offsetUs, 0);
    });
  });

  group('MinRttTracker', () {
    test('first ping becomes the best estimate', () {
      final tracker = MinRttTracker();
      tracker.add(
        OffsetEstimate.compute(
          t1AppUs: 1000000,
          t2DeviceUs: 1004000,
          t3AppUs: 1010000,
        ),
      );
      expect(tracker.count, 1);
      expect(tracker.best, isNotNull);
      expect(tracker.best!.rttMs, 10.0);
    });

    test('keeps the estimate with the lowest RTT', () {
      final tracker = MinRttTracker()
        ..add(
          OffsetEstimate.compute(
            t1AppUs: 1000000,
            t2DeviceUs: 1004000,
            t3AppUs: 1020000, // RTT 20 ms
          ),
        )
        ..add(
          OffsetEstimate.compute(
            t1AppUs: 2000000,
            t2DeviceUs: 2002000,
            t3AppUs: 2005000, // RTT 5 ms — better
          ),
        )
        ..add(
          OffsetEstimate.compute(
            t1AppUs: 3000000,
            t2DeviceUs: 3003000,
            t3AppUs: 3012000, // RTT 12 ms — worse
          ),
        );

      expect(tracker.count, 3);
      expect(tracker.best!.rttMs, 5.0);
      // offset = T2 - (T1 + RTT_us/2) = 2002000 - (2000000 + 2500) = -500
      expect(tracker.best!.offsetUs, -500);
    });

    test('best is null before any ping', () {
      expect(MinRttTracker().best, isNull);
    });

    test('clear resets the tracker', () {
      final tracker = MinRttTracker()
        ..add(
          OffsetEstimate.compute(
            t1AppUs: 1000000,
            t2DeviceUs: 1004000,
            t3AppUs: 1010000,
          ),
        );
      tracker.clear();
      expect(tracker.count, 0);
      expect(tracker.best, isNull);
    });
  });

  group('DriftFit', () {
    test('perfect 1:1 fit (no drift) → slope=1, intercept=0, residual=0', () {
      // t_app_us = 1.0 * t_device_us + 0
      // Points: (1000000 us, 1000000 us), (2000000, 2000000), (3000000, 3000000)
      final fit = DriftFit.fit([
        const SyncPoint(tDeviceUs: 1000000, tAppUs: 1000000),
        const SyncPoint(tDeviceUs: 2000000, tAppUs: 2000000),
        const SyncPoint(tDeviceUs: 3000000, tAppUs: 3000000),
      ]);
      expect(fit.slope, closeTo(1.0, 1e-12));
      expect(fit.interceptUs, closeTo(0, 1e-6));
      expect(fit.residualRmsMs, closeTo(0, 1e-9));
      expect(fit.n, 3);
    });

    test('fit with constant offset → intercept = offset', () {
      // t_app_us = t_device_us + 500000 (500 ms offset)
      final fit = DriftFit.fit([
        const SyncPoint(tDeviceUs: 1000000, tAppUs: 1500000),
        const SyncPoint(tDeviceUs: 2000000, tAppUs: 2500000),
        const SyncPoint(tDeviceUs: 3000000, tAppUs: 3500000),
      ]);
      expect(fit.slope, closeTo(1.0, 1e-12));
      expect(fit.interceptUs, closeTo(500000, 1e-3));
      expect(fit.residualRmsMs, closeTo(0, 1e-9));
    });

    test('fit with drift (slope != 1.0)', () {
      // Device clock runs 0.1% fast: t_app_us = (1/1.001) * t_device_us
      // So at t_device_us = 1001000, t_app_us = 1000000
      final fit = DriftFit.fit([
        const SyncPoint(tDeviceUs: 1001000, tAppUs: 1000000),
        const SyncPoint(tDeviceUs: 2002000, tAppUs: 2000000),
        const SyncPoint(tDeviceUs: 3003000, tAppUs: 3000000),
      ]);
      expect(fit.slope, closeTo(1.0 / 1.001, 1e-9));
      expect(fit.interceptUs, closeTo(0, 1e-3));
    });

    test('residualRmsMs measures fit quality with noise', () {
      // Perfect line + 1 ms (1000 us) noise on one point
      final fit = DriftFit.fit([
        const SyncPoint(tDeviceUs: 1000000, tAppUs: 1000000),
        const SyncPoint(tDeviceUs: 2000000, tAppUs: 2001000), // +1 ms noise
        const SyncPoint(tDeviceUs: 3000000, tAppUs: 3000000),
      ]);
      expect(fit.slope, closeTo(1.0, 1e-6));
      // Residual RMS should be small but nonzero.
      expect(fit.residualRmsMs, greaterThan(0));
      expect(fit.residualRmsMs, lessThan(1.0));
    });

    test('throws ArgumentError for fewer than 2 points', () {
      expect(
        () => DriftFit.fit([const SyncPoint(tDeviceUs: 0, tAppUs: 0)]),
        throwsArgumentError,
      );
      expect(() => DriftFit.fit([]), throwsArgumentError);
    });

    test('toSyncedMs converts device timestamp to common timeline (ms)', () {
      final fit = DriftFit.fit([
        const SyncPoint(tDeviceUs: 1000000, tAppUs: 1500000),
        const SyncPoint(tDeviceUs: 2000000, tAppUs: 2500000),
      ]);
      // t_app_us = slope * t_device_us + intercept = 1.0 * 1500000 + 500000 = 2000000
      // toSyncedMs = 2000000 / 1000 = 2000 ms
      expect(fit.toSyncedMs(1500000), closeTo(2000, 1e-3));
    });

    test('toSyncedUs converts device timestamp to common timeline (us)', () {
      final fit = DriftFit.fit([
        const SyncPoint(tDeviceUs: 1000000, tAppUs: 1500000),
        const SyncPoint(tDeviceUs: 2000000, tAppUs: 2500000),
      ]);
      expect(fit.toSyncedUs(1500000), closeTo(2000000, 1.0));
    });
  });

  group('ScheduledStart.compute (§3.2)', () {
    test('converts phone start time to device local micros', () {
      // From §3.2:
      // target_start_us = (T_start_phone - t_app_ref_ms) * 1000
      //                   + offset_us + t_device_ref_us
      //
      // Example: T_start_phone = 5000 ms, t_app_ref = 1000 ms,
      // offset = 5000 us, t_device_ref = 1000000 us
      // target = (5000 - 1000) * 1000 + 5000 + 1000000
      //        = 4000000 + 5000 + 1000000 = 5005000
      final target = ScheduledStart.compute(
        tStartPhoneMs: 5000,
        tAppRefMs: 1000,
        offsetUs: 5000,
        tDeviceRefUs: 1000000,
      );
      expect(target, 5005000);
    });

    test('works with negative offset (device behind phone)', () {
      final target = ScheduledStart.compute(
        tStartPhoneMs: 5000,
        tAppRefMs: 1000,
        offsetUs: -3000,
        tDeviceRefUs: 1000000,
      );
      // (5000-1000)*1000 + (-3000) + 1000000 = 4000000 - 3000 + 1000000 = 4997000
      expect(target, 4997000);
    });

    test('immediate start (T_start = t_app_ref) → offset + t_device_ref', () {
      final target = ScheduledStart.compute(
        tStartPhoneMs: 1000,
        tAppRefMs: 1000,
        offsetUs: 5000,
        tDeviceRefUs: 1000000,
      );
      expect(target, 5000 + 1000000);
    });
  });

  group('SyncPoint', () {
    test('is immutable and has value equality', () {
      const a = SyncPoint(tDeviceUs: 100, tAppUs: 200);
      const b = SyncPoint(tDeviceUs: 100, tAppUs: 200);
      expect(a, b);
      expect(a.tDeviceUs, 100);
      expect(a.tAppUs, 200);
    });
  });
}
