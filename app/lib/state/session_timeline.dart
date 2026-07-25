import 'package:wheelathlete/state/sync_engine.dart';

/// Maps uint32 board timestamps onto the synchronized, START-relative
/// training timeline. Board uptime is never interpreted as UTC.
class SessionTimeline {
  const SessionTimeline._();

  static const int _modulus = 0x100000000;

  /// Forward uint32 delta, including one `micros()` wrap.
  static int deviceDeltaUs(int timestampUs, int startUs) =>
      (timestampUs - startUs) & (_modulus - 1);

  /// START-relative microseconds. A final drift slope is applied when it is
  /// trustworthy; otherwise the raw device delta is the explicit degraded
  /// fallback.
  static int relativeUs({
    required int timestampUs,
    required int startUs,
    DriftFit? driftFit,
  }) {
    final delta = deviceDeltaUs(timestampUs, startUs);
    final slope = driftFit?.slope;
    if (slope == null || !slope.isFinite || slope < 0.95 || slope > 1.05) {
      return delta;
    }
    return (delta * slope).round();
  }

  /// Difference between two START acknowledgements after each board clock is
  /// mapped to the phone/common timeline. Raw board uptime counters must not
  /// be subtracted from one another.
  static int? commonStartDeltaUs({
    required int? leftStartUs,
    required int? rightStartUs,
    required DriftFit? leftFit,
    required DriftFit? rightFit,
  }) {
    if (leftStartUs == null ||
        rightStartUs == null ||
        leftFit == null ||
        rightFit == null) {
      return null;
    }
    return (leftFit.toSyncedUs(leftStartUs) - rightFit.toSyncedUs(rightStartUs))
        .abs()
        .round();
  }
}
