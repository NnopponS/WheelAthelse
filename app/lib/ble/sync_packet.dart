import 'dart:typed_data';

import 'package:wheelathlete/ble/ble_uuids.dart';

/// Sync event IDs from the Sync characteristic (protocol §4.4).
///
/// The firmware prepends the event_id byte to every Sync notification
/// (verified in `firmware/src/ble_service.cpp:handleSyncPing` —
/// `packSyncEvent(SyncEvent::SyncResponse, buf, 12, event_buf)` produces
/// 13 bytes: `[0x00][12-byte response]`).
class SyncEventId {
  const SyncEventId._(); // coverage:ignore-line

  static const int syncResponse = 0x00;
  static const int dropCount = 0x10;
  static const int cmdNack = 0x20;
  static const int startFired = 0x30;
  static const int stopFired = 0x40;
}

/// Parsed Sync characteristic notification (§4.4).
///
/// Sealed union: the byte 0 `event_id` determines which subclass is
/// returned by [SyncEvent.parse]. Each carries its typed payload.
sealed class SyncEvent {
  const SyncEvent();

  /// Parses a Sync notify payload `[event_id][event-specific data...]`.
  ///
  /// Throws [ArgumentError] if the buffer is empty or the payload is
  /// truncated for the given event_id. Throws [FormatException] if the
  /// event_id is not one of the values in §4.4.
  factory SyncEvent.parse(List<int> bytes) {
    if (bytes.isEmpty) {
      throw ArgumentError('Sync event buffer is empty', 'bytes');
    }
    final id = bytes[0];
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    switch (id) {
      case SyncEventId.syncResponse:
        // [0x00][t_app_ms u32@1][t_device_us u32@5][seq_ping u32@9] = 13B
        if (bytes.length < 1 + BleUuids.syncResponseSize) {
          throw ArgumentError(
            'SYNC_RESPONSE needs ${1 + BleUuids.syncResponseSize} bytes, '
            'got ${bytes.length}',
            'bytes',
          );
        }
        return SyncResponseEvent(
          tAppMs: data.getUint32(1, Endian.little),
          tDeviceUs: data.getUint32(5, Endian.little),
          seqPing: data.getUint32(9, Endian.little),
        );
      case SyncEventId.dropCount:
        // [0x10][count u32@1] = 5B
        if (bytes.length < 5) {
          throw ArgumentError(
            'DROP_COUNT needs 5 bytes, got ${bytes.length}',
            'bytes',
          );
        }
        return DropCountEvent(count: data.getUint32(1, Endian.little));
      case SyncEventId.cmdNack:
        // [0x20][cmd u8@1] = 2B
        if (bytes.length < 2) {
          throw ArgumentError(
            'CMD_NACK needs 2 bytes, got ${bytes.length}',
            'bytes',
          );
        }
        return CmdNackEvent(cmd: data.getUint8(1));
      case SyncEventId.startFired:
        // [0x30][t_device_us u32@1] = 5B
        if (bytes.length < 5) {
          throw ArgumentError(
            'START_FIRED needs 5 bytes, got ${bytes.length}',
            'bytes',
          );
        }
        return StartFiredEvent(tDeviceUs: data.getUint32(1, Endian.little));
      case SyncEventId.stopFired:
        // [0x40][t_device_us u32@1][last_seq u32@5] = 9B
        if (bytes.length < 9) {
          throw ArgumentError(
            'STOP_FIRED needs 9 bytes, got ${bytes.length}',
            'bytes',
          );
        }
        return StopFiredEvent(
          tDeviceUs: data.getUint32(1, Endian.little),
          lastSeq: data.getUint32(5, Endian.little),
        );
      default:
        throw FormatException(
          'Unknown Sync event_id 0x${id.toRadixString(16).padLeft(2, '0')}',
        );
    }
  }
}

/// §4.1 Sync response: echo of SYNC_PING with device timestamp + ping seq.
final class SyncResponseEvent extends SyncEvent {
  const SyncResponseEvent({
    required this.tAppMs,
    required this.tDeviceUs,
    required this.seqPing,
  });

  /// Phone timestamp (ms) echoed from the SYNC_PING command.
  final int tAppMs;

  /// `micros()` on the M5 when it received/responded to the ping.
  final int tDeviceUs;

  /// Ping sequence number (increments per ping per device).
  final int seqPing;
}

/// §4.4 DROP_COUNT: number of samples dropped since the last event.
final class DropCountEvent extends SyncEvent {
  const DropCountEvent({required this.count});
  final int count;
}

/// §4.4 CMD_NACK: the firmware rejected an unknown/invalid command byte.
final class CmdNackEvent extends SyncEvent {
  const CmdNackEvent({required this.cmd});
  final int cmd;
}

/// §4.4 START_FIRED: firmware confirmed acquisition started at this device
/// time. Used to cross-check that both wheels started together.
final class StartFiredEvent extends SyncEvent {
  const StartFiredEvent({required this.tDeviceUs});
  final int tDeviceUs;
}

/// §4.4 STOP_FIRED: firmware confirmed acquisition stopped + last seq.
final class StopFiredEvent extends SyncEvent {
  const StopFiredEvent({required this.tDeviceUs, required this.lastSeq});
  final int tDeviceUs;
  final int lastSeq;
}
