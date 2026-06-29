import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/state/sync_engine.dart';

void main() {
  group('OffsetEstimate.compute (§4.2)', () {
    test('zero offset when device time = phone time + RTT/2', () {
      // T1 = 1000 ms (phone sends ping)
      // T2 = 1000000 us (device receives — = 1000 ms * 1000 = 1000000 us)
      // T3 = 1008 ms (phone receives response — RTT = 8 ms)
      // offset = T2 - (T1*1000 + RTT_us/2) = 1000000 - (1000000 + 4000) = -4000 us
      // Wait — that's not zero. Let me think again.
      //
      // If device clock == phone clock (both in us), and RTT is symmetric:
      // T1_us = 1000000, T2_us = 1000000 + 4000 (device receives 4ms later),
      // T3_us = 1000000 + 8000. RTT = 8000 us. offset = T2 - (T1 + RTT/2)
      // = 1004000 - (1000000 + 4000) = 0. Correct!
      final est = OffsetEstimate.compute(
        t1AppMs: 1000,
        t2DeviceUs: 1004000,
        t3AppMs: 1008,
      );
      expect(est.rttMs, 8.0);
      expect(est.offsetUs, 0);
    });

    test('positive offset when device clock is ahead of phone', () {
      // Device clock is 5000 us (5 ms) ahead.
      // T1 = 1000 ms, T2 = 1004000 + 5000 = 1009000 us, T3 = 1008 ms
      // offset = 1009000 - (1000000 + 4000) = 5000 us
      final est = OffsetEstimate.compute(
        t1AppMs: 1000,
        t2DeviceUs: 1009000,
        t3AppMs: 1008,
      );
      expect(est.rttMs, 8.0);
      expect(est.offsetUs, 5000);
    });

    test('negative offset when device clock is behind phone', () {
      // Device clock is 3000 us (3 ms) behind.
      // T1 = 1000 ms, T2 = 1004000 - 3000 = 1001000 us, T3 = 1008 ms
      // offset = 1001000 - (1000000 + 4000) = -3000 us
      final est = OffsetEstimate.compute(
        t1AppMs: 1000,
        t2DeviceUs: 1001000,
        t3AppMs: 1008,
      );
      expect(est.rttMs, 8.0);
      expect(est.offsetUs, -3000);
    });

    test('RTT is always non-negative (T3 >= T1)', () {
      final est = OffsetEstimate.compute(
        t1AppMs: 1000,
        t2DeviceUs: 1000000,
        t3AppMs: 1000, // RTT = 0 (instant)
      );
      expect(est.rttMs, 0.0);
    });
  });

  group('MinRttTracker', () {
    test('first ping becomes the best estimate', () {
      final tracker = MinRttTracker();
      tracker.add(OffsetEstimate.compute(
        t1AppMs: 1000,
        t2DeviceUs: 1004000,
        t3AppMs: 1010,
      ));
      expect(tracker.count, 1);
      expect(tracker.best, isNotNull);
      expect(tracker.best!.rttMs, 10.0);
    });

    test('keeps the estimate with the lowest RTT', () {
      final tracker = MinRttTracker()
        ..add(OffsetEstimate.compute(
          t1AppMs: 1000,
          t2DeviceUs: 1004000,
          t3AppMs: 1020, // RTT 20 ms
        ))
        ..add(OffsetEstimate.compute(
          t1AppMs: 2000,
          t2DeviceUs: 2002000,
          t3AppMs: 2005, // RTT 5 ms — better
        ))
        ..add(OffsetEstimate.compute(
          t1AppMs: 3000,
          t2DeviceUs: 3003000,
          t3AppMs: 3012, // RTT 12 ms — worse
        ));

      expect(tracker.count, 3);
      expect(tracker.best!.rttMs, 5.0);
      // offset = T2 - (T1*1000 + RTT_us/2)
      // = 2002000 - (2000000 + 2500) = -500
      expect(tracker.best!.offsetUs, -500);
    });

    test('best is null before any ping', () {
      expect(MinRttTracker().best, isNull);
    });

    test('clear resets the tracker', () {
      final tracker = MinRttTracker()
        ..add(OffsetEstimate.compute(
          t1AppMs: 1000,
          t2DeviceUs: 1004000,
          t3AppMs: 1010,
        ));
      tracker.clear();
      expect(tracker.count, 0);
      expect(tracker.best, isNull);
    });
  });

  group('DriftFit', () {
    test('perfect 1:1 fit (no drift) → slope=1, intercept=0, residual=0', () {
      // t_app_ms = 1.0 * t_device_us / 1000 + 0
      // Points: (1000000 us, 1000 ms), (2000000, 2000), (3000000, 3000)
      final fit = DriftFit.fit([
        const SyncPoint(tDeviceUs: 1000000, tAppMs: 1000),
        const SyncPoint(tDeviceUs: 2000000, tAppMs: 2000),
        const SyncPoint(tDeviceUs: 3000000, tAppMs: 3000),
      ]);
      expect(fit.slope, closeTo(1.0 / 1000.0, 1e-12));
      expect(fit.interceptMs, closeTo(0, 1e-9));
      expect(fit.residualRmsMs, closeTo(0, 1e-9));
      expect(fit.n, 3);
    });

    test('fit with constant offset → intercept = offset', () {
      // t_app_ms = t_device_us / 1000 + 500
      final fit = DriftFit.fit([
        const SyncPoint(tDeviceUs: 1000000, tAppMs: 1500),
        const SyncPoint(tDeviceUs: 2000000, tAppMs: 2500),
        const SyncPoint(tDeviceUs: 3000000, tAppMs: 3500),
      ]);
      expect(fit.slope, closeTo(1.0 / 1000.0, 1e-12));
      expect(fit.interceptMs, closeTo(500, 1e-9));
      expect(fit.residualRmsMs, closeTo(0, 1e-9));
    });

    test('fit with drift (slope != 1/1000)', () {
      // Device clock runs 0.1% fast: t_app_ms = (1/1001) * t_device_us
      // So at t_device_us = 1001000, t_app_ms = 1000
      final fit = DriftFit.fit([
        const SyncPoint(tDeviceUs: 1001000, tAppMs: 1000),
        const SyncPoint(tDeviceUs: 2002000, tAppMs: 2000),
        const SyncPoint(tDeviceUs: 3003000, tAppMs: 3000),
      ]);
      expect(fit.slope, closeTo(1.0 / 1001.0, 1e-9));
      expect(fit.interceptMs, closeTo(0, 1e-6));
    });

    test('residualRmsMs measures fit quality with noise', () {
      // Perfect line + 1 ms noise on one point
      final fit = DriftFit.fit([
        const SyncPoint(tDeviceUs: 1000000, tAppMs: 1000),
        const SyncPoint(tDeviceUs: 2000000, tAppMs: 2001), // +1 ms noise
        const SyncPoint(tDeviceUs: 3000000, tAppMs: 3000),
      ]);
      expect(fit.slope, closeTo(1.0 / 1000.0, 1e-6));
      // Residual RMS should be small but nonzero.
      expect(fit.residualRmsMs, greaterThan(0));
      expect(fit.residualRmsMs, lessThan(1.0));
    });

    test('throws ArgumentError for fewer than 2 points', () {
      expect(
        () => DriftFit.fit([const SyncPoint(tDeviceUs: 0, tAppMs: 0)]),
        throwsArgumentError,
      );
      expect(() => DriftFit.fit([]), throwsArgumentError);
    });

    test('toSyncedMs converts device timestamp to common timeline', () {
      final fit = DriftFit.fit([
        const SyncPoint(tDeviceUs: 1000000, tAppMs: 1500),
        const SyncPoint(tDeviceUs: 2000000, tAppMs: 2500),
      ]);
      // t_app_ms = slope * t_device_us + intercept
      // = (1/1000) * 1500000 + 500 = 2000
      expect(fit.toSyncedMs(1500000), closeTo(2000, 1e-6));
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
      const a = SyncPoint(tDeviceUs: 100, tAppMs: 200);
      const b = SyncPoint(tDeviceUs: 100, tAppMs: 200);
      expect(a, b);
      expect(a.tDeviceUs, 100);
      expect(a.tAppMs, 200);
    });
  });
}
