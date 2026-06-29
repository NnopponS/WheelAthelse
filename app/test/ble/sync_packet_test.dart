import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/ble/sync_packet.dart';

/// Builds a Sync notify payload: [event_id][payload...]
Uint8List _event(int eventId, List<int> payload) =>
    Uint8List.fromList([eventId, ...payload]);

/// Builds the inner 12-byte sync response (§4.1) then prepends 0x00 event_id.
Uint8List _syncResponseEvent({
  required int tAppMs,
  required int tDeviceUs,
  required int seqPing,
}) {
  final inner = ByteData(12)
    ..setUint32(0, tAppMs, Endian.little)
    ..setUint32(4, tDeviceUs, Endian.little)
    ..setUint32(8, seqPing, Endian.little);
  return _event(0x00, inner.buffer.asUint8List());
}

void main() {
  group('SyncEvent.parse', () {
    test('parses SYNC_RESPONSE (0x00) with 12B payload at offsets 1/5/9', () {
      final bytes = _syncResponseEvent(
        tAppMs: 1000000,
        tDeviceUs: 2000000,
        seqPing: 7,
      );
      expect(bytes.length, 13); // 1 event_id + 12 payload

      final event = SyncEvent.parse(bytes);
      expect(event, isA<SyncResponseEvent>());
      final r = event as SyncResponseEvent;
      expect(r.tAppMs, 1000000);
      expect(r.tDeviceUs, 2000000);
      expect(r.seqPing, 7);
    });

    test('parses DROP_COUNT (0x10) with uint32 count at offset 1', () {
      final bytes = _event(0x10, [..._u32LE(42)]);
      expect(bytes.length, 5);

      final event = SyncEvent.parse(bytes);
      expect(event, isA<DropCountEvent>());
      expect((event as DropCountEvent).count, 42);
    });

    test('parses CMD_NACK (0x20) with uint8 cmd at offset 1', () {
      final bytes = _event(0x20, [0x99]);
      expect(bytes.length, 2);

      final event = SyncEvent.parse(bytes);
      expect(event, isA<CmdNackEvent>());
      expect((event as CmdNackEvent).cmd, 0x99);
    });

    test('parses START_FIRED (0x30) with uint32 t_device_us at offset 1', () {
      final bytes = _event(0x30, [..._u32LE(5000000)]);
      expect(bytes.length, 5);

      final event = SyncEvent.parse(bytes);
      expect(event, isA<StartFiredEvent>());
      expect((event as StartFiredEvent).tDeviceUs, 5000000);
      expect(event.utcStartMs, 0); // legacy 5-byte format → 0
    });

    test('parses extended START_FIRED (v1.1.0) with utc_start_ms at offset 5', () {
      final bytes = _event(0x30, [
        ..._u32LE(5000000),
        ..._u64LE(1719691200456),
      ]);
      expect(bytes.length, 13);

      final event = SyncEvent.parse(bytes);
      expect(event, isA<StartFiredEvent>());
      final s = event as StartFiredEvent;
      expect(s.tDeviceUs, 5000000);
      expect(s.utcStartMs, 1719691200456);
    });

    test('parses START_FIRED with utc_start_ms=0 when UTC not set', () {
      final bytes = _event(0x30, [..._u32LE(5000000), ..._u64LE(0)]);
      final s = SyncEvent.parse(bytes) as StartFiredEvent;
      expect(s.tDeviceUs, 5000000);
      expect(s.utcStartMs, 0);
    });

    test('parses UTC_SET (0x50) with uint64 utc_epoch_ms at offset 1', () {
      final bytes = _event(0x50, [..._u64LE(1719691200000)]);
      expect(bytes.length, 9);

      final event = SyncEvent.parse(bytes);
      expect(event, isA<UtcSetEvent>());
      expect((event as UtcSetEvent).utcEpochMs, 1719691200000);
    });

    test('UTC_SET with zero epoch', () {
      final bytes = _event(0x50, [..._u64LE(0)]);
      final event = SyncEvent.parse(bytes) as UtcSetEvent;
      expect(event.utcEpochMs, 0);
    });

    test('parses STOP_FIRED (0x40) with t_device_us@1 + last_seq@5', () {
      final bytes = _event(0x40, [..._u32LE(6000000), ..._u32LE(9999)]);
      expect(bytes.length, 9);

      final event = SyncEvent.parse(bytes);
      expect(event, isA<StopFiredEvent>());
      final s = event as StopFiredEvent;
      expect(s.tDeviceUs, 6000000);
      expect(s.lastSeq, 9999);
    });

    test('throws FormatException for unknown event_id', () {
      expect(
        () => SyncEvent.parse(_event(0x99, [0x00])),
        throwsFormatException,
      );
    });

    test('throws ArgumentError on empty buffer', () {
      expect(() => SyncEvent.parse(Uint8List(0)), throwsArgumentError);
    });

    test('throws ArgumentError when SYNC_RESPONSE payload is truncated', () {
      // 0x00 + only 8 bytes instead of 12
      expect(
        () => SyncEvent.parse(_event(0x00, [0, 0, 0, 0, 0, 0, 0, 0])),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError when DROP_COUNT payload is truncated', () {
      // 0x10 + only 2 bytes instead of 4
      expect(
        () => SyncEvent.parse(_event(0x10, [0, 0])),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError when START_FIRED payload is truncated', () {
      expect(
        () => SyncEvent.parse(_event(0x30, [0, 0, 0])),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError when UTC_SET payload is truncated', () {
      expect(
        () => SyncEvent.parse(_event(0x50, [0, 0, 0])),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError when STOP_FIRED payload is truncated', () {
      // 0x40 + only 5 bytes instead of 8
      expect(
        () => SyncEvent.parse(_event(0x40, [0, 0, 0, 0, 0])),
        throwsArgumentError,
      );
    });

    test('handles uint32 max values in SYNC_RESPONSE', () {
      final bytes = _syncResponseEvent(
        tAppMs: 0xFFFFFFFF,
        tDeviceUs: 0xFFFFFFFF,
        seqPing: 0xFFFFFFFF,
      );
      final r = SyncEvent.parse(bytes) as SyncResponseEvent;
      expect(r.tAppMs, 0xFFFFFFFF);
      expect(r.tDeviceUs, 0xFFFFFFFF);
      expect(r.seqPing, 0xFFFFFFFF);
    });
  });

  group('SyncEvent.eventId constants', () {
    test('match the protocol §4.4 values', () {
      expect(SyncEventId.syncResponse, 0x00);
      expect(SyncEventId.dropCount, 0x10);
      expect(SyncEventId.cmdNack, 0x20);
      expect(SyncEventId.startFired, 0x30);
      expect(SyncEventId.stopFired, 0x40);
      expect(SyncEventId.utcSet, 0x50);
    });
  });
}

List<int> _u32LE(int v) {
  final b = ByteData(4)..setUint32(0, v, Endian.little);
  return b.buffer.asUint8List();
}

List<int> _u64LE(int v) {
  final b = ByteData(8)..setUint64(0, v, Endian.little);
  return b.buffer.asUint8List();
}
