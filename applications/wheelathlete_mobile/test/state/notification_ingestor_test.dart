import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/ble/imu_batch_processor.dart';
import 'package:wheelathlete/ble/imu_packet.dart';
import 'package:wheelathlete/state/sample_hub.dart';

class _EchoProcessor implements ImuBatchProcessor {
  @override
  FutureOr<ProcessedImuBatch> parse(List<int> bytes) {
    final seq = bytes.first;
    final sample = ImuSample(
      seq: seq,
      tDeviceUs: seq * 1000,
      ax: 0,
      ay: 0,
      az: 0,
      gx: 0,
      gy: 0,
      gz: 0,
    );
    return ProcessedImuBatch(samples: [sample], readings: const [], newGaps: 0);
  }

  @override
  Future<void> dispose() async {}
}

class _BlockingProcessor implements ImuBatchProcessor {
  final Completer<void> gate = Completer<void>();

  @override
  Future<ProcessedImuBatch> parse(List<int> bytes) async {
    await gate.future;
    return const ProcessedImuBatch(samples: [], readings: [], newGaps: 0);
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  test('raw notification ingestor preserves callback order', () async {
    final seqs = <int>[];
    final errors = <Object>[];
    final ingestor = RawNotificationIngestor(
      processor: _EchoProcessor(),
      onBatch: (batch, _) => seqs.addAll(batch.samples.map((s) => s.seq)),
      onError: (error, _) => errors.add(error),
    );
    addTearDown(ingestor.dispose);

    for (var i = 0; i < 100; i++) {
      expect(ingestor.enqueue([i], i), isTrue);
    }
    await ingestor.join();

    expect(seqs, List<int>.generate(100, (i) => i));
    expect(errors, isEmpty);
    expect(ingestor.metrics.notificationsReceived, 100);
    expect(ingestor.metrics.queueHighWater, greaterThan(0));
  });

  test(
    'bounded ingress fails closed instead of overwriting unread data',
    () async {
      final processor = _BlockingProcessor();
      final errors = <Object>[];
      final ingestor = RawNotificationIngestor(
        processor: processor,
        capacity: 2,
        onBatch: (_, _) {},
        onError: (error, _) => errors.add(error),
      );

      expect(ingestor.enqueue([1], 1), isTrue);
      expect(ingestor.enqueue([2], 2), isTrue);
      expect(ingestor.enqueue([3], 3), isFalse);
      expect(ingestor.metrics.queueHighWater, 2);
      expect(ingestor.metrics.queueOverflowFaults, 1);
      expect(errors.single, isA<HostIngressOverflowException>());

      processor.gate.complete();
      await ingestor.join();
      await ingestor.dispose();
    },
  );
}
