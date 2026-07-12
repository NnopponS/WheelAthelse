import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/state/live_acquisition_providers.dart';

void main() {
  test('starting and stopping acquisition are not toggleable', () {
    expect(
      const LiveAcquisitionState(status: LiveAcquisitionStatus.starting)
          .canToggle,
      isFalse,
    );
    expect(
      const LiveAcquisitionState(status: LiveAcquisitionStatus.stopping)
          .canToggle,
      isFalse,
    );
    expect(
      const LiveAcquisitionState(status: LiveAcquisitionStatus.live).canToggle,
      isTrue,
    );
  });
}
