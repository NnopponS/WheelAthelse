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
  static const int countdownCue = 0x31;
  static const int stopFired = 0x40;
  static const int utcSet = 0x50;
  static const int acqHealth = 0x60;
  static const int replayResult = 0x61;
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
        // v1.1.0 extended: [0x30][t_device_us u32@1][utc_start_ms u64@5] = 13B
        // v1.0.0 legacy:   [0x30][t_device_us u32@1] = 5B (no UTC stamp)
        if (bytes.length >= 13) {
          return StartFiredEvent(
            tDeviceUs: data.getUint32(1, Endian.little),
            utcStartMs: data.getUint64(5, Endian.little),
          );
        } else if (bytes.length >= 5) {
          // Legacy 5-byte format (UTC not set / old firmware)
          return StartFiredEvent(
            tDeviceUs: data.getUint32(1, Endian.little),
            utcStartMs: 0,
          );
        } else {
          throw ArgumentError(
            'START_FIRED needs at least 5 bytes, got ${bytes.length}',
            'bytes',
          );
        }
      case SyncEventId.countdownCue:
        // [0x31][index u8][total u8][duration_ms u16] = 5B
        if (bytes.length < 5) {
          throw ArgumentError(
            'COUNTDOWN_CUE needs 5 bytes, got ${bytes.length}',
            'bytes',
          );
        }
        return CountdownCueEvent(
          index: data.getUint8(1),
          total: data.getUint8(2),
          durationMs: data.getUint16(3, Endian.little),
        );
      case SyncEventId.utcSet:
        // [0x50][utc_epoch_ms u64@1] = 9B
        if (bytes.length < 9) {
          throw ArgumentError(
            'UTC_SET needs 9 bytes, got ${bytes.length}',
            'bytes',
          );
        }
        return UtcSetEvent(utcEpochMs: data.getUint64(1, Endian.little));
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
      case SyncEventId.acqHealth:
        // Protocol 1.5 used 0x60 for REPLAY_RESULT. Preserve that exact
        // 10-byte payload while reserving 0x60 for ACQ_HEALTH in 1.6.
        if (bytes.length == 10) {
          return ReplayResultEvent(
            startSeq: data.getUint32(1, Endian.little),
            requested: data.getUint16(5, Endian.little),
            replayed: data.getUint16(7, Endian.little),
            status: data.getUint8(9),
          );
        }
        if (bytes.length != 20 && bytes.length != 28) {
          throw ArgumentError(
            'ACQ_HEALTH needs 20 or 28 bytes, got ${bytes.length}',
            'bytes',
          );
        }
        return AcqHealthEvent(
          acquisitionState: data.getUint8(1),
          producedSamples: data.getUint32(2, Endian.little),
          notifiedSamples: data.getUint32(6, Endian.little),
          queueDrops: data.getUint32(10, Endian.little),
          transportFailures: data.getUint32(14, Endian.little),
          queueDepth: data.getUint16(18, Endian.little),
          fifoFaults: bytes.length >= 28
              ? data.getUint32(20, Endian.little)
              : 0,
          fifoDroppedSamples: bytes.length >= 28
              ? data.getUint32(24, Endian.little)
              : 0,
        );
      case SyncEventId.replayResult:
        if (bytes.length != 10) {
          throw ArgumentError(
            'REPLAY_RESULT needs 10 bytes, got ${bytes.length}',
            'bytes',
          );
        }
        return ReplayResultEvent(
          startSeq: data.getUint32(1, Endian.little),
          requested: data.getUint16(5, Endian.little),
          replayed: data.getUint16(7, Endian.little),
          status: data.getUint8(9),
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
/// v1.1.0: includes `utcStartMs` (UTC epoch ms, 0 if UTC not set).
final class StartFiredEvent extends SyncEvent {
  const StartFiredEvent({required this.tDeviceUs, this.utcStartMs = 0});
  final int tDeviceUs;
  final int utcStartMs;
}

/// Firmware countdown feedback. Both M5 speaker beeps and XIAO LED flashes
/// emit this event so the phone can play one matching audible cue.
final class CountdownCueEvent extends SyncEvent {
  const CountdownCueEvent({
    required this.index,
    required this.total,
    required this.durationMs,
  });
  final int index;
  final int total;
  final int durationMs;
  bool get isStart => total > 0 && index == total - 1;
}

/// §4.4 STOP_FIRED: firmware confirmed acquisition stopped + last seq.
final class StopFiredEvent extends SyncEvent {
  const StopFiredEvent({required this.tDeviceUs, required this.lastSeq});
  final int tDeviceUs;
  final int lastSeq;
}

/// §4.4 UTC_SET (v1.1.0): firmware echoes back the UTC epoch ms set via
/// SET_UTC command. App uses this to confirm the board received the UTC time.
final class UtcSetEvent extends SyncEvent {
  const UtcSetEvent({required this.utcEpochMs});
  final int utcEpochMs;
}

/// Protocol 1.3 result for a REPLAY_RANGE request.
final class ReplayResultEvent extends SyncEvent {
  const ReplayResultEvent({
    required this.startSeq,
    required this.requested,
    required this.replayed,
    required this.status,
  });
  final int startSeq;
  final int requested;
  final int replayed;
  final int status;
  bool get complete => status == 0 && replayed == requested;
}

/// Protocol 1.8.0 acquisition health snapshot, emitted at 1 Hz and on STOP.
final class AcqHealthEvent extends SyncEvent {
  const AcqHealthEvent({
    required this.acquisitionState,
    required this.producedSamples,
    required this.notifiedSamples,
    required this.queueDrops,
    required this.transportFailures,
    required this.queueDepth,
    this.fifoFaults = 0,
    this.fifoDroppedSamples = 0,
  });

  final int acquisitionState;
  final int producedSamples;
  final int notifiedSamples;
  final int queueDrops;
  final int transportFailures;
  final int queueDepth;
  final int fifoFaults;
  final int fifoDroppedSamples;
}
