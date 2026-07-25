import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wheelathlete/ble/ble_repository.dart';
import 'package:wheelathlete/ble/control_command.dart';
import 'package:wheelathlete/ble/sync_packet.dart';
import 'package:wheelathlete/state/ble_providers.dart';
import 'package:wheelathlete/state/sync_engine.dart';
import 'package:wheelathlete/theme/theme.dart';

/// Delay between retries when a transient Android GATT write rejects STOP.
final stopCommandRetryDelayProvider = Provider<Duration>(
  (ref) => const Duration(milliseconds: 100),
);

class StopWriteResult {
  const StopWriteResult({
    required this.written,
    required this.attempts,
    this.error,
  });

  final bool written;
  final int attempts;
  final Object? error;
}

/// Per-wheel clock-sync state surfaced to the UI and recording layer.
class WheelSyncState {
  const WheelSyncState({
    this.syncing = false,
    this.offset,
    this.driftFit,
    this.pendingPing,
    this.dropCount = 0,
    this.lastStartFiredUs,
    this.lastStopFiredUs,
    this.lastSeq,
    this.utcEpochMs,
    this.utcStartMs,
    this.acqHealth,
    this.error,
  });

  /// Whether we are actively listening for Sync events from this wheel.
  final bool syncing;

  /// Best (min-RTT) offset estimate so far, or null if no ping completed.
  final OffsetEstimate? offset;

  /// Linear drift fit from collected sync points, or null if < 2 points.
  final DriftFit? driftFit;

  /// The ping currently awaiting a Sync response (T1 recorded), or null.
  final PendingPing? pendingPing;

  /// Cumulative drop count from DROP_COUNT events.
  final int dropCount;

  /// Last START_FIRED event's device timestamp (cross-check both wheels).
  final int? lastStartFiredUs;

  /// Last STOP_FIRED event's device timestamp.
  final int? lastStopFiredUs;

  /// Last seq from STOP_FIRED event.
  final int? lastSeq;

  /// UTC epoch ms set via SET_UTC (confirmed by UTC_SET echo), or null.
  final int? utcEpochMs;

  /// UTC start instant from extended START_FIRED (v1.1.0), for camera alignment.
  final int? utcStartMs;

  /// Latest protocol 1.6 firmware health snapshot.
  final AcqHealthEvent? acqHealth;

  /// Error message from a NACK, parse failure, or stream error.
  final String? error;

  WheelSyncState copyWith({
    bool? syncing,
    OffsetEstimate? offset,
    DriftFit? driftFit,
    Object? pendingPing = _unset,
    int? dropCount,
    int? lastStartFiredUs,
    int? lastStopFiredUs,
    int? lastSeq,
    Object? utcEpochMs = _unset,
    Object? utcStartMs = _unset,
    Object? acqHealth = _unset,
    Object? error = _unset,
  }) => WheelSyncState(
    syncing: syncing ?? this.syncing,
    offset: offset ?? this.offset,
    driftFit: driftFit ?? this.driftFit,
    pendingPing: identical(pendingPing, _unset)
        ? this.pendingPing
        : pendingPing as PendingPing?,
    dropCount: dropCount ?? this.dropCount,
    lastStartFiredUs: lastStartFiredUs ?? this.lastStartFiredUs,
    lastStopFiredUs: lastStopFiredUs ?? this.lastStopFiredUs,
    lastSeq: lastSeq ?? this.lastSeq,
    utcEpochMs: identical(utcEpochMs, _unset)
        ? this.utcEpochMs
        : utcEpochMs as int?,
    utcStartMs: identical(utcStartMs, _unset)
        ? this.utcStartMs
        : utcStartMs as int?,
    acqHealth: identical(acqHealth, _unset)
        ? this.acqHealth
        : acqHealth as AcqHealthEvent?,
    error: identical(error, _unset) ? this.error : error as String?,
  );

  static const Object _unset = Object();
}

/// A ping sent but not yet answered. Holds T1 in both ms (for protocol
/// matching — the device echoes back ms) and µs (for sub-ms offset
/// computation).
class PendingPing {
  const PendingPing({
    required this.t1AppMs,
    required this.t1AppUs,
    required this.sentAt,
  });

  /// Phone time in ms sent to the device (protocol field is uint32 ms).
  final int t1AppMs;

  /// Phone time in µs since epoch — used for sub-ms offset computation.
  final int t1AppUs;

  final DateTime sentAt;
}

/// Whole sync state: per-side snapshots.
class SyncEngineState {
  SyncEngineState({Map<WheelSide, WheelSyncState>? bySide})
    : bySide = {
        WheelSide.left: bySide?[WheelSide.left] ?? const WheelSyncState(),
        WheelSide.right: bySide?[WheelSide.right] ?? const WheelSyncState(),
      };

  final Map<WheelSide, WheelSyncState> bySide;

  SyncEngineState copyWithSide(WheelSide side, WheelSyncState value) =>
      SyncEngineState(bySide: {...bySide, side: value});

  static SyncEngineState initial() => SyncEngineState();
}

/// Orchestrates clock sync for both wheels.
///
/// - [sendPing]: writes SYNC_PING via Control, records T1, waits for the
///   Sync response to compute offset (§4.2).
/// - [startListening]: subscribes to the Sync notify stream for event
///   notifications (START_FIRED, STOP_FIRED, DROP_COUNT, CMD_NACK).
/// - [sendStart] / [sendStop] / [sendResetSeq]: write Control commands.
///
/// The notifier tracks per-side [MinRttTracker] + [SyncPoint] list and
/// exposes the current [DriftFit] once ≥ 2 points are collected.
class SyncEngineNotifier extends Notifier<SyncEngineState> {
  final _subs = <WheelSide, StreamSubscription<List<int>>>{};
  final _channels = <WheelSide, BleNotificationChannel<List<int>>>{};
  final _trackers = <WheelSide, MinRttTracker>{};
  final _points = <WheelSide, List<SyncPoint>>{};
  final Map<WheelSide, List<Completer<int>>> _startWaiters = {};
  final Map<WheelSide, List<Completer<int>>> _stopWaiters = {};

  /// Reference phone timestamp (ms since epoch) captured on the first ping.
  /// All t_app_ms values sent to the firmware are relative to this reference
  /// so they fit in the protocol's uint32 field (§4.1).
  int? _tAppRefMs;

  /// Reference phone timestamp (µs since epoch) captured on the first ping.
  /// Used for sub-ms offset computation. Kept in sync with [_tAppRefMs].
  int? _tAppRefUs;

  /// Exposes the reference phone timestamp so other providers (e.g. the
  /// countdown notifier) can convert absolute phone ms to the same relative
  /// timeline the sync engine uses. Returns null if no ping has been sent.
  int? get tAppRefMs => _tAppRefMs;

  /// Exposes the reference phone timestamp in µs for sub-ms computations.
  int? get tAppRefUs => _tAppRefUs;

  @override
  SyncEngineState build() {
    ref.onDispose(() {
      for (final s in _subs.values) {
        s.cancel();
      }
      for (final channel in _channels.values) {
        unawaited(channel.close());
      }
      _subs.clear();
      _trackers.clear();
      _points.clear();
      _startWaiters.clear();
      _stopWaiters.clear();
    });
    return SyncEngineState.initial();
  }

  BleRepository get _ble => ref.read(bleRepositoryProvider);

  /// Sends a SYNC_PING to [side]'s device and records T1.
  ///
  /// The Sync response (received via the stream from [startListening] or a
  /// ping-specific listener) completes the round trip and updates the
  /// offset estimate. If the wheel is not connected, sets an error.
  Future<void> sendPing(WheelSide side) async {
    final conn = ref.read(connectionManagerProvider).bySide[side]!;
    final deviceId = conn.deviceId;
    if (deviceId == null) {
      state = state.copyWithSide(
        side,
        const WheelSyncState(error: 'Wheel not connected'),
      );
      return;
    }

    // Ensure we're listening for Sync responses.
    await _ensureListening(side);

    // Use a relative timestamp so it fits in the protocol's uint32 t_app_ms
    // field (§4.1). Absolute Unix epoch ms in 2026 (~1.78e12) overflows
    // uint32 (max ~4.29e9). Relative ms since first ping fits for ~49 days.
    //
    // We capture both ms (for the protocol field) and µs (for sub-ms offset
    // computation) at the same instant.
    final nowUs = DateTime.now().microsecondsSinceEpoch;
    final nowMs = nowUs ~/ 1000;
    _tAppRefMs ??= nowMs;
    _tAppRefUs ??= nowUs;
    final t1AppMs = nowMs - _tAppRefMs!;
    final t1AppUs = nowUs - _tAppRefUs!;
    state = state.copyWithSide(
      side,
      state.bySide[side]!.copyWith(
        pendingPing: PendingPing(
          t1AppMs: t1AppMs,
          t1AppUs: t1AppUs,
          sentAt: DateTime.now(),
        ),
        error: null,
      ),
    );

    await _ble.writeControl(deviceId, ControlCommand.syncPing(t1AppMs));
  }

  /// Starts listening for Sync event notifications on [side].
  ///
  /// Idempotent — if already listening, does nothing.
  Future<void> startListening(WheelSide side) async {
    await _ensureListening(side);
  }

  Future<bool> waitForStart(
    WheelSide side, {
    required int? previous,
    required Duration timeout,
  }) => _waitForAck(
    side,
    previous: previous,
    timeout: timeout,
    waiters: _startWaiters,
    current: () => state.bySide[side]!.lastStartFiredUs,
  );

  Future<bool> waitForStop(
    WheelSide side, {
    required int? previous,
    required Duration timeout,
  }) => _waitForAck(
    side,
    previous: previous,
    timeout: timeout,
    waiters: _stopWaiters,
    current: () => state.bySide[side]!.lastStopFiredUs,
  );

  Future<bool> _waitForAck(
    WheelSide side, {
    required int? previous,
    required Duration timeout,
    required Map<WheelSide, List<Completer<int>>> waiters,
    required int? Function() current,
  }) async {
    if (current() != previous) return true;
    final completer = Completer<int>();
    (waiters[side] ??= <Completer<int>>[]).add(completer);
    try {
      await completer.future.timeout(timeout);
      return true;
    } on TimeoutException {
      return false;
    } finally {
      waiters[side]?.remove(completer);
    }
  }

  Future<void> _ensureListening(WheelSide side) async {
    if (_subs[side] != null) return; // already listening

    final conn = ref.read(connectionManagerProvider).bySide[side]!;
    final deviceId = conn.deviceId;
    if (deviceId == null) {
      state = state.copyWithSide(
        side,
        const WheelSyncState(error: 'Wheel not connected'),
      );
      return;
    }

    _trackers[side] = MinRttTracker();
    _points[side] = [];
    state = state.copyWithSide(side, const WheelSyncState(syncing: true));

    final channel = _ble.syncNotifications(deviceId);
    _channels[side] = channel;
    _subs[side] = channel.stream.listen(
      (bytes) {
        try {
          final event = SyncEvent.parse(bytes);
          _handleEvent(side, event);
        } on Object catch (e) {
          if (!ref.mounted) return;
          state = state.copyWithSide(
            side,
            state.bySide[side]!.copyWith(error: 'Sync parse error: $e'),
          );
        }
      },
      onError: (Object e) {
        if (!ref.mounted) return;
        state = state.copyWithSide(
          side,
          state.bySide[side]!.copyWith(
            syncing: false,
            error: 'Sync stream error: $e',
          ),
        );
        _subs.remove(side);
      },
    );
    try {
      await channel.ready;
    } on Object catch (error) {
      await _subs.remove(side)?.cancel();
      _channels.remove(side);
      if (ref.mounted) {
        state = state.copyWithSide(
          side,
          state.bySide[side]!.copyWith(
            syncing: false,
            error: 'Sync notification setup failed: $error',
          ),
        );
      }
      rethrow;
    }
  }

  void _handleEvent(WheelSide side, SyncEvent event) {
    if (!ref.mounted) return;
    final cur = state.bySide[side]!;

    switch (event) {
      case SyncResponseEvent(:final tAppMs, :final tDeviceUs):
        // Complete the pending ping if it matches.
        final pending = cur.pendingPing;
        if (pending == null || pending.t1AppMs != tAppMs) {
          // Stale or unmatched response — ignore.
          break;
        }
        // Capture T3 in µs for sub-ms offset precision. The protocol sends
        // T1 in ms (uint32 constraint), but we compute the offset using
        // µs-precision T1 and T3 to avoid 1ms quantization error.
        final t3AppUs =
            DateTime.now().microsecondsSinceEpoch - (_tAppRefUs ?? 0);
        final estimate = OffsetEstimate.compute(
          t1AppUs: pending.t1AppUs,
          t2DeviceUs: tDeviceUs,
          t3AppUs: t3AppUs,
        );
        _trackers[side]!.add(estimate);
        _points[side]!.add(SyncPoint(tDeviceUs: tDeviceUs, tAppUs: t3AppUs));
        final driftFit = _points[side]!.length >= 2
            ? DriftFit.fit(_points[side]!)
            : null;
        state = state.copyWithSide(
          side,
          cur.copyWith(
            offset: _trackers[side]!.best,
            driftFit: driftFit,
            pendingPing: null,
            error: null,
          ),
        );
      case DropCountEvent(:final count):
        state = state.copyWithSide(
          side,
          cur.copyWith(dropCount: cur.dropCount + count),
        );
      case CmdNackEvent(:final cmd):
        state = state.copyWithSide(
          side,
          cur.copyWith(
            error: 'CMD_NACK: firmware rejected cmd 0x${cmd.toRadixString(16)}',
          ),
        );
      case StartFiredEvent(:final tDeviceUs, :final utcStartMs):
        state = state.copyWithSide(
          side,
          cur.copyWith(lastStartFiredUs: tDeviceUs),
        );
        // Store UTC start instant for session meta (camera alignment)
        if (utcStartMs > 0) {
          state = state.copyWithSide(
            side,
            state.bySide[side]!.copyWith(utcStartMs: utcStartMs),
          );
        }
        for (final waiter
            in _startWaiters.remove(side) ?? const <Completer<int>>[]) {
          if (!waiter.isCompleted) waiter.complete(tDeviceUs);
        }
      case CountdownCueEvent():
        // RecordCountdownNotifier consumes and deduplicates audible cues.
        break;
      case StopFiredEvent(:final tDeviceUs, :final lastSeq):
        state = state.copyWithSide(
          side,
          cur.copyWith(lastStopFiredUs: tDeviceUs, lastSeq: lastSeq),
        );
        for (final waiter
            in _stopWaiters.remove(side) ?? const <Completer<int>>[]) {
          if (!waiter.isCompleted) waiter.complete(tDeviceUs);
        }
      case UtcSetEvent(:final utcEpochMs):
        // Confirm UTC was received by the board
        state = state.copyWithSide(side, cur.copyWith(utcEpochMs: utcEpochMs));
      case ReplayResultEvent():
        // Sample recovery completion is consumed by the shared sample hub;
        // keep the sync state unchanged.
        break;
      case AcqHealthEvent():
        state = state.copyWithSide(side, cur.copyWith(acqHealth: event));
    }
  }

  /// Sends a START command with [targetStartUs] (§3.1, §3.2).
  ///
  /// Pass 0 for immediate start, or a scheduled device-local micros value
  /// computed via [ScheduledStart.compute] for synchronized start.
  Future<void> sendStart(WheelSide side, {required int targetStartUs}) async {
    final deviceId = _deviceIdOrError(side);
    if (deviceId == null) return;
    await _ble.writeControl(deviceId, ControlCommand.start(targetStartUs));
  }

  /// Sends a STOP command (§3.1).
  Future<void> sendStop(WheelSide side) async {
    final deviceId = _deviceIdOrError(side);
    if (deviceId == null) return;
    await _ble.writeControl(deviceId, ControlCommand.stop());
  }

  /// Sends STOP with bounded retries. A caller should send to each wheel
  /// serially, then wait for all STOP_FIRED acknowledgements concurrently.
  Future<StopWriteResult> sendStopWithRetry(
    WheelSide side, {
    int maxAttempts = 3,
  }) async {
    Object? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        await sendStop(side);
        return StopWriteResult(written: true, attempts: attempt);
      } on Object catch (error) {
        lastError = error;
      }

      if (attempt < maxAttempts) {
        final delay = ref.read(stopCommandRetryDelayProvider) * attempt;
        if (delay > Duration.zero) await Future<void>.delayed(delay);
      }
    }
    return StopWriteResult(
      written: false,
      attempts: maxAttempts,
      error: lastError,
    );
  }

  /// Sends a RESET_SEQ command (§3.1).
  Future<void> sendResetSeq(WheelSide side) async {
    final deviceId = _deviceIdOrError(side);
    if (deviceId == null) return;
    await _ble.writeControl(deviceId, ControlCommand.resetSeq());
  }

  String? _deviceIdOrError(WheelSide side) {
    final conn = ref.read(connectionManagerProvider).bySide[side]!;
    if (conn.deviceId == null) {
      state = state.copyWithSide(
        side,
        const WheelSyncState(error: 'Wheel not connected'),
      );
      return null;
    }
    return conn.deviceId;
  }
}

final syncEngineProvider =
    NotifierProvider<SyncEngineNotifier, SyncEngineState>(
      SyncEngineNotifier.new,
    );
