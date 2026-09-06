import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/ble/imu_packet.dart';
import 'package:wheelathlete/state/sample_hub.dart';

ImuSample sample(int seq) => ImuSample(
  seq: seq,
  tDeviceUs: seq * 1000,
  ax: 0,
  ay: 0,
  az: 0,
  gx: 0,
  gy: 0,
  gz: 0,
);

void main() {
  test('requests and merges a missing range without duplicates', () async {
    final output = <HubSample>[];
    final requests = <(int, int)>[];
    final buffer = SampleRecoveryBuffer(
      onSample: output.add,
      onReplay: (start, count) async => requests.add((start, count)),
    );
    addTearDown(buffer.dispose);
    buffer.add(sample(10), 1);
    buffer.add(sample(13), 2);
    await Future<void>.delayed(Duration.zero);
    expect(requests, [(11, 2)]);
    buffer.add(sample(11), 3);
    buffer.add(sample(12), 4);
    buffer.add(sample(12), 5); // duplicate replay
    expect(output.map((event) => event.sample.seq), [10, 11, 12, 13]);
    expect(buffer.metrics.recoveredSamples, 2);
    expect(buffer.metrics.unrecoveredSamples, 0);
  });

  test('orders a replay across uint32 wraparound', () {
    final output = <HubSample>[];
    final buffer = SampleRecoveryBuffer(
      onSample: output.add,
      onReplay: (_, _) async {},
    );
    addTearDown(buffer.dispose);
    buffer.add(sample(0xFFFFFFFE), 1);
    buffer.add(sample(1), 2);
    buffer.add(sample(0xFFFFFFFF), 3);
    buffer.add(sample(0), 4);
    expect(output.map((event) => event.sample.seq), [
      0xFFFFFFFE,
      0xFFFFFFFF,
      0,
      1,
    ]);
  });

  test(
    'never starts a second replay write while the first is in flight',
    () async {
      final firstWrite = Completer<void>();
      var writes = 0;
      final buffer = SampleRecoveryBuffer(
        timeout: const Duration(milliseconds: 10),
        onSample: (_) {},
        onReplay: (_, _) async {
          writes++;
          await firstWrite.future;
        },
      );
      addTearDown(buffer.dispose);

      buffer.add(sample(10), 1);
      buffer.add(sample(13), 2);
      await Future<void>.delayed(const Duration(milliseconds: 35));

      expect(writes, 1);
      firstWrite.complete();
      await Future<void>.delayed(Duration.zero);
    },
  );

  test(
    'contains replay write failures and does not mislabel live samples',
    () async {
      final write = Completer<void>();
      final output = <HubSample>[];
      final buffer = SampleRecoveryBuffer(
        timeout: const Duration(milliseconds: 10),
        onSample: output.add,
        onReplay: (_, _) => write.future,
      );
      addTearDown(buffer.dispose);

      buffer.add(sample(10), 1);
      buffer.add(sample(13), 2);
      write.completeError(StateError('GATT_INSUFFICIENT_RESOURCES'));
      await Future<void>.delayed(Duration.zero);
      buffer.add(sample(11), 3);
      buffer.add(sample(12), 4);

      expect(output.map((event) => event.sample.seq), [10, 11, 12, 13]);
      expect(buffer.metrics.recoveredSamples, 0);
      expect(buffer.metrics.replayWriteFailures, 1);
    },
  );

  test(
    'suspend waits for the active replay and prevents retry writes',
    () async {
      final write = Completer<void>();
      var writes = 0;
      final buffer = SampleRecoveryBuffer(
        timeout: const Duration(milliseconds: 10),
        onSample: (_) {},
        onReplay: (_, _) {
          writes++;
          return write.future;
        },
      );
      addTearDown(buffer.dispose);

      buffer.add(sample(10), 1);
      buffer.add(sample(13), 2);
      final suspended = buffer.suspendReplay(
        drainTimeout: const Duration(milliseconds: 100),
      );
      write.completeError(StateError('transport busy'));
      await suspended;
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(writes, 1);
      expect(buffer.metrics.replayWriteFailures, 1);
    },
  );
}
