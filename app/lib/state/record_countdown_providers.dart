import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wheelathlete/ble/ble_repository.dart';
import 'package:wheelathlete/ble/control_command.dart';
import 'package:wheelathlete/ble/sync_packet.dart';
import 'package:wheelathlete/records/session_model.dart';
import 'package:wheelathlete/state/ble_providers.dart';
import 'package:wheelathlete/state/recording_providers.dart';
import 'package:wheelathlete/state/sync_engine.dart';
import 'package:wheelathlete/state/sync_providers.dart';
import 'package:wheelathlete/theme/theme.dart';
import 'package:wheelathlete/widgets/connection_card.dart';

/// Status of the record countdown state machine (subtask #16).
///
/// Flow: idle → syncing → counting → recording → stopped.
/// Cancel path: counting → idle (sends STOP before T_start).
enum RecordCountdownStatus { idle, syncing, counting, recording, stopped, error }

/// State surfaced to the countdown UI.
class RecordCountdownState {
  const RecordCountdownState({
    this.status = RecordCountdownStatus.idle,
    this.countdownSeconds = 0,
    this.tStartPhoneMs,
    this.utcStartMs,
    this.error,
  });

  final RecordCountdownStatus status;

  /// Current countdown number shown in-app (5 → 1, 0 at T_start).
  final int countdownSeconds;

  /// Scheduled start instant on the phone clock (epoch ms), or null when
  /// no countdown is active.
  final int? tStartPhoneMs;

  /// UTC epoch ms of the scheduled start instant (for session meta), or null.
  final int? utcStartMs;

  final String? error;

  RecordCountdownState copyWith({
    RecordCountdownStatus? status,
    int? countdownSeconds,
    Object? tStartPhoneMs = _unset,
    Object? utcStartMs = _unset,
    Object? error = _unset,
  }) =>
      RecordCountdownState(
        status: status ?? this.status,
        countdownSeconds: countdownSeconds ?? this.countdownSeconds,
        tStartPhoneMs: identical(tStartPhoneMs, _unset)
            ? this.tStartPhoneMs
            : tStartPhoneMs as int?,
        utcStartMs:
            identical(utcStartMs, _unset) ? this.utcStartMs : utcStartMs as int?,
        error: identical(error, _unset) ? this.error : error as String?,
      );

  static const Object _unset = Object();
}

/// Number of SYNC_PING round trips sent to each wheel during the sync burst
/// before a scheduled start. More pings → better min-RTT offset estimate.
const int kSyncBurstCount = 5;

/// Interval between SYNC_PINGs in the burst (ms). Short enough to keep the
/// burst under ~250ms, long enough for the firmware to echo each one.
const Duration kSyncBurstInterval = Duration(milliseconds: 30);

/// Countdown duration before the scheduled start. The in-app UI shows
/// 5-4-3-2-1; the firmware beeps 3-2-1 on the M5 speaker.
const Duration kCountdownDuration = Duration(seconds: 5);

/// Notifier that orchestrates the record countdown flow (subtask #16):
///
/// 1. **syncing** — sends a SYNC_PING burst to both wheels to refresh the
///    min-RTT offset estimate (§4.2).
/// 2. Sends SET_UTC to both wheels with the phone's current UTC epoch ms.
/// 3. Computes `T_start = now_phone + countdownDuration` and the
///    corresponding UTC start instant (`utc_start_ms`).
/// 4. Sends a scheduled START (via [ScheduledStart.compute]) to both wheels
///    so they begin acquisition together at T_start. The firmware beeps
///    3-2-1 during its own countdown.
/// 5. **counting** — shows 5-4-3-2-1 in-app (cancellable). On cancel, sends
///    STOP to both wheels before T_start and returns to idle.
/// 6. On START_FIRED from both wheels, hands off to [RecordingNotifier] to
///    begin buffering IMU samples → **recording**.
class RecordCountdownNotifier extends Notifier<RecordCountdownState> {
  Timer? _displayTimer;
  Timer? _startTimer;
  final _startFiredSubs = <WheelSide, StreamSubscription<List<int>>>{};
  final _startFired = <WheelSide, bool>{};
  SessionConfig? _pendingConfig;
  int? _utcStartMs;
  int? _utcOffsetMs;
  bool _cancelled = false;

  @override
  RecordCountdownState build() {
    ref.onDispose(() {
      _displayTimer?.cancel();
      _startTimer?.cancel();
      for (final s in _startFiredSubs.values) {
        s.cancel();
      }
      _startFiredSubs.clear();
    });
    return const RecordCountdownState();
  }

  BleRepository get _ble => ref.read(bleRepositoryProvider);

  /// Begins the countdown flow for [config]. At least one wheel must be
  /// connected — works with a single wheel or both.
  ///
  /// Sends a SYNC_PING burst, SET_UTC, and a scheduled START to every
  /// connected wheel, then drives the in-app countdown. On START_FIRED
  /// from all connected wheels, delegates to [RecordingNotifier.startRecording]
  /// with the UTC start stamp baked into the config.
  Future<void> start(SessionConfig config) async {
    if (state.status != RecordCountdownStatus.idle &&
        state.status != RecordCountdownStatus.stopped &&
        state.status != RecordCountdownStatus.error) {
      throw StateError('Countdown already in progress');
    }
    _cancelled = false;
    _pendingConfig = config;
    _startFired
      ..clear()
      ..[WheelSide.left] = false
      ..[WheelSide.right] = false;
    state = const RecordCountdownState(status: RecordCountdownStatus.syncing);

    final connState = ref.read(connectionManagerProvider);
    // Build the list of connected wheels (at least one required).
    final connectedSides = <WheelSide>[];
    for (final side in WheelSide.values) {
      if (connState.bySide[side]!.deviceId != null &&
          connState.bySide[side]!.status == ConnectionStatus.connected) {
        connectedSides.add(side);
      }
    }
    if (connectedSides.isEmpty) {
      state = const RecordCountdownState(
        status: RecordCountdownStatus.error,
        error: 'At least one wheel must be connected to start a countdown',
      );
      return;
    }

    // 1. SYNC_PING burst to refresh offset estimates (connected wheels only).
    final sync = ref.read(syncEngineProvider.notifier);
    for (var i = 0; i < kSyncBurstCount; i++) {
      if (_cancelled) return;
      for (final side in connectedSides) {
        await sync.sendPing(side);
      }
      if (i < kSyncBurstCount - 1) {
        await Future<void>.delayed(kSyncBurstInterval);
      }
    }
    if (_cancelled || !ref.mounted) return;

    // 2. Capture phone + UTC instants and compute T_start + utc_start_ms.
    final nowPhoneMs = DateTime.now().millisecondsSinceEpoch;
    final utcEpochNowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    final countdownMs = ref.read(countdownDurationProvider).inMilliseconds;
    // Align to the next whole second before the countdown begins so the
    // scheduled start always lands on a .000 boundary (camera sync).
    final nextWholeSecondMs = ((nowPhoneMs + 999) ~/ 1000) * 1000;
    final tStartPhoneMs = nextWholeSecondMs + countdownMs;
    final utcStartMs = computeUtcStartMs(
      utcEpochNowMs: utcEpochNowMs,
      nowPhoneMs: nowPhoneMs,
      tStartPhoneMs: tStartPhoneMs,
    );
    // The drift-fit timeline uses _tAppRefMs as its origin. utcStartMs is the
    // UTC instant of the scheduled start, so the offset that converts any
    // relative synced ms to absolute UTC is utcStartMs - tStartRelMs.
    final tAppRefMs = sync.tAppRefMs ?? nowPhoneMs;
    final tStartRelMs = tStartPhoneMs - tAppRefMs;
    _utcStartMs = utcStartMs;
    _utcOffsetMs = utcStartMs - tStartRelMs;

    // 3. Send SET_UTC to every connected wheel.
    for (final side in connectedSides) {
      final deviceId = connState.bySide[side]!.deviceId!;
      await _ble.writeControl(deviceId, ControlCommand.setUtc(utcEpochNowMs));
      if (_cancelled || !ref.mounted) return;
    }

    // 4. Send scheduled START to every connected wheel (firmware beeps 3-2-1).
    for (final side in connectedSides) {
      await _sendScheduledStart(side, tStartPhoneMs);
      if (_cancelled || !ref.mounted) return;
    }

    // 5. Subscribe to START_FIRED events from every connected wheel.
    for (final side in connectedSides) {
      final deviceId = connState.bySide[side]!.deviceId!;
      await _subscribeStartFired(side, deviceId);
    }

    // 6. Begin the in-app countdown display.
    state = RecordCountdownState(
      status: RecordCountdownStatus.counting,
      countdownSeconds: (countdownMs / 1000).ceil(),
      tStartPhoneMs: tStartPhoneMs,
      utcStartMs: utcStartMs,
    );
    _startDisplayTimer(tStartPhoneMs);
  }

  Future<void> _sendScheduledStart(WheelSide side, int tStartPhoneMs) async {
    final sync = ref.read(syncEngineProvider.notifier);
    final syncState = ref.read(syncEngineProvider).bySide[side]!;
    final offset = syncState.offset;
    if (offset == null) {
      // No offset estimate — fall back to immediate start (target=0).
      await sync.sendStart(side, targetStartUs: 0);
      return;
    }
    // The sync engine uses a *relative* phone timeline (ms since first ping)
    // to avoid uint32 overflow in the protocol. We must convert T_start
    // (absolute epoch ms) to the same relative timeline before computing
    // the device-local target micros.
    final tAppRefMs = sync.tAppRefMs ?? tStartPhoneMs;
    final tStartRelMs = tStartPhoneMs - tAppRefMs;
    // tDeviceRefUs = 0 because the offset already accounts for the device
    // reference point (offset = T2_device - (T1_app_rel*1000 + RTT/2)).
    const tDeviceRefUs = 0;
    final targetStartUs = ScheduledStart.compute(
      tStartPhoneMs: tStartRelMs,
      tAppRefMs: 0, // already relative
      offsetUs: offset.offsetUs,
      tDeviceRefUs: tDeviceRefUs,
    );
    await sync.sendStart(side, targetStartUs: targetStartUs);
  }

  void _startDisplayTimer(int tStartPhoneMs) {
    _displayTimer?.cancel();
    _displayTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!ref.mounted || _cancelled) {
        _displayTimer?.cancel();
        return;
      }
      final remainingMs = tStartPhoneMs - DateTime.now().millisecondsSinceEpoch;
      if (remainingMs <= 0) {
        _displayTimer?.cancel();
        state = state.copyWith(countdownSeconds: 0);
        return;
      }
      final seconds = (remainingMs / 1000).ceil();
      if (seconds != state.countdownSeconds) {
        state = state.copyWith(countdownSeconds: seconds);
      }
    });
  }

  Future<void> _subscribeStartFired(WheelSide side, String deviceId) async {
    await _startFiredSubs[side]?.cancel();
    _startFiredSubs[side] = _ble.syncData(deviceId).listen(
      (bytes) {
        try {
          final event = SyncEvent.parse(bytes);
          if (event is StartFiredEvent) {
            _onStartFired(side);
          }
        } on Object {
          // Parse errors are handled by the sync engine; ignore here.
        }
      },
      onError: (Object e) {
        if (!ref.mounted) return;
        state = state.copyWith(
          status: RecordCountdownStatus.error,
          error: 'Sync stream error ($side): $e',
        );
      },
    );
  }

  void _onStartFired(WheelSide side) {
    if (!ref.mounted || _cancelled) return;
    _startFired[side] = true;
    // Start recording when all *connected* wheels have fired.
    final allFired = _startFired.entries
        .where((e) => _startFiredSubs.containsKey(e.key))
        .every((e) => e.value);
    if (allFired) {
      _beginRecording();
    }
  }

  Future<void> _beginRecording() async {
    _displayTimer?.cancel();
    for (final s in _startFiredSubs.values) {
      await s.cancel();
    }
    _startFiredSubs.clear();
    if (!ref.mounted || _cancelled || _pendingConfig == null) return;
    state = state.copyWith(status: RecordCountdownStatus.recording);
    final startTime = _utcStartMs != null
        ? DateTime.fromMillisecondsSinceEpoch(_utcStartMs!, isUtc: true)
        : DateTime.now();
    final config = SessionConfig(
      topic: _pendingConfig!.topic,
      trialNumber: _pendingConfig!.trialNumber,
      sampleRateHz: _pendingConfig!.sampleRateHz,
      athleteName: _pendingConfig!.athleteName,
      notes: _pendingConfig!.notes,
      utcStartMs: _utcStartMs,
      utcOffsetMs: _utcOffsetMs,
      protocolTemplateId: _pendingConfig!.protocolTemplateId,
      startTime: startTime,
    );
    try {
      await ref.read(recordingProvider.notifier).startRecording(config);
    } on Object catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(
        status: RecordCountdownStatus.error,
        error: 'Failed to begin recording: $e',
      );
    }
  }

  /// Cancels an in-progress countdown. Sends STOP to both wheels before
  /// T_start and returns to idle. No-op if not counting/syncing.
  Future<void> cancel() async {
    if (state.status != RecordCountdownStatus.syncing &&
        state.status != RecordCountdownStatus.counting) {
      return;
    }
    _cancelled = true;
    _displayTimer?.cancel();
    for (final s in _startFiredSubs.values) {
      await s.cancel();
    }
    _startFiredSubs.clear();
    // Send STOP to both wheels in case a scheduled START was already sent.
    final sync = ref.read(syncEngineProvider.notifier);
    try {
      await sync.sendStop(WheelSide.left);
      await sync.sendStop(WheelSide.right);
    } on Object {
      // Best-effort — the wheels may not have started yet.
    }
    if (!ref.mounted) return;
    _utcStartMs = null;
    _utcOffsetMs = null;
    state = const RecordCountdownState(status: RecordCountdownStatus.idle);
  }

  /// Resets to idle after recording stops (called when RecordingNotifier
  /// transitions to stopped, or manually to clear an error).
  void reset() {
    _displayTimer?.cancel();
    for (final s in _startFiredSubs.values) {
      s.cancel();
    }
    _startFiredSubs.clear();
    _cancelled = false;
    _pendingConfig = null;
    _utcStartMs = null;
    _utcOffsetMs = null;
    state = const RecordCountdownState();
  }
}

/// Countdown duration before the scheduled start. Override in tests to a
/// short duration so the countdown completes quickly.
final countdownDurationProvider = Provider<Duration>(
  (ref) => kCountdownDuration,
);

final recordCountdownProvider =
    NotifierProvider<RecordCountdownNotifier, RecordCountdownState>(
  RecordCountdownNotifier.new,
);
