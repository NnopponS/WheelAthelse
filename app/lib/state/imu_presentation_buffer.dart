import 'dart:collection';

import 'package:wheelathlete/ble/imu_packet.dart';

/// Immutable UI snapshot of one wheel's bounded presentation buffer.
class ImuPresentationSnapshot {
  const ImuPresentationSnapshot({
    required this.latest,
    required this.sampleCount,
    required this.dropCount,
    required this.recent,
  });

  final ImuReading? latest;
  final int sampleCount;
  final int dropCount;
  final List<ImuReading> recent;
}

/// Fixed-capacity circular buffer used only for realtime presentation.
///
/// [add] is O(1) and does not copy chart history. The ordered list is created
/// only when [snapshot] is called at the UI refresh rate. This keeps the BLE
/// notification callback bounded even during sustained dual-wheel 200 Hz
/// acquisition; the independent recording sink still receives every sample.
class ImuPresentationBuffer {
  ImuPresentationBuffer({required int capacity})
    : assert(capacity > 0),
      _slots = List<ImuReading?>.filled(capacity, null);

  final List<ImuReading?> _slots;
  var _writeIndex = 0;
  var _length = 0;
  var _sampleCount = 0;
  var _dropCount = 0;
  ImuReading? _latest;

  void add(ImuReading reading, {required int dropCount}) {
    _slots[_writeIndex] = reading;
    _writeIndex = (_writeIndex + 1) % _slots.length;
    if (_length < _slots.length) _length++;
    _sampleCount++;
    _dropCount = dropCount;
    _latest = reading;
  }

  ImuPresentationSnapshot snapshot() {
    final oldest = (_writeIndex - _length) % _slots.length;
    final ordered = List<ImuReading>.generate(
      _length,
      (index) => _slots[(oldest + index) % _slots.length]!,
      growable: false,
    );
    return ImuPresentationSnapshot(
      latest: _latest,
      sampleCount: _sampleCount,
      dropCount: _dropCount,
      recent: UnmodifiableListView(ordered),
    );
  }

  void reset() {
    for (var index = 0; index < _slots.length; index++) {
      _slots[index] = null;
    }
    _writeIndex = 0;
    _length = 0;
    _sampleCount = 0;
    _dropCount = 0;
    _latest = null;
  }
}
