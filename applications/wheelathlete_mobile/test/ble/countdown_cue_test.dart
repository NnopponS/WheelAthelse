import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/ble/sync_packet.dart';
import 'package:wheelathlete/state/countdown_cue_player.dart';

void main() {
  test('parses a countdown cue emitted by firmware', () {
    final event = SyncEvent.parse([0x31, 3, 4, 0xF4, 0x01]);

    expect(event, isA<CountdownCueEvent>());
    final cue = event as CountdownCueEvent;
    expect(cue.index, 3);
    expect(cue.total, 4);
    expect(cue.durationMs, 500);
    expect(cue.isStart, isTrue);
  });

  test('deduplicates the same cue received from two boards', () {
    final deduplicator = CountdownCueDeduplicator()..reset();

    expect(deduplicator.accept(0), isTrue);
    expect(deduplicator.accept(0), isFalse);
    expect(deduplicator.accept(1), isTrue);
    deduplicator.reset();
    expect(deduplicator.accept(0), isTrue);
  });
}
