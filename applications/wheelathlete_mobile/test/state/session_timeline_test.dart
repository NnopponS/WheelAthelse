import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/state/session_timeline.dart';
import 'package:wheelathlete/state/sync_engine.dart';

void main() {
  test('maps a timestamp across uint32 micros wrap', () {
    expect(
      SessionTimeline.relativeUs(startUs: 0xFFFFFF00, timestampUs: 0x00000100),
      512,
    );
  });

  test('applies final drift slope to START-relative delta', () {
    const fit = DriftFit(
      slope: 1.001,
      interceptUs: 123456,
      residualRmsMs: 0.2,
      n: 8,
    );
    expect(
      SessionTimeline.relativeUs(
        startUs: 4000000000,
        timestampUs: 4001000000,
        driftFit: fit,
      ),
      1001000,
    );
  });

  test('compares different board uptimes only after common mapping', () {
    const leftFit = DriftFit(
      slope: 1,
      interceptUs: -1000000,
      residualRmsMs: 0.1,
      n: 5,
    );
    const rightFit = DriftFit(
      slope: 1,
      interceptUs: -9000000,
      residualRmsMs: 0.1,
      n: 5,
    );
    expect(
      SessionTimeline.commonStartDeltaUs(
        leftStartUs: 2000000,
        rightStartUs: 10000000,
        leftFit: leftFit,
        rightFit: rightFit,
      ),
      0,
    );
  });

  test('does not report raw-uptime start quality without both fits', () {
    expect(
      SessionTimeline.commonStartDeltaUs(
        leftStartUs: 2000000,
        rightStartUs: 10000000,
        leftFit: null,
        rightFit: null,
      ),
      isNull,
    );
  });
}
