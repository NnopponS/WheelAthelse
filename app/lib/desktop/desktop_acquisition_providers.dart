import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wheelathlete/desktop/daemon_client.dart';

class DesktopPreviewSample {
  const DesktopPreviewSample({
    required this.side,
    required this.seq,
    required this.deviceUs,
    required this.pcNs,
    required this.ax,
    required this.ay,
    required this.az,
    required this.gx,
    required this.gy,
    required this.gz,
  });

  final String side;
  final int seq;
  final int deviceUs;
  final int pcNs;
  final int ax;
  final int ay;
  final int az;
  final int gx;
  final int gy;
  final int gz;

  factory DesktopPreviewSample.fromPayload(Map<String, dynamic> payload) {
    int value(String key) => (payload[key] as num?)?.toInt() ?? 0;
    return DesktopPreviewSample(
      side: '${payload['side'] ?? ''}',
      seq: value('seq'),
      deviceUs: value('timestamp_device_us'),
      pcNs: value('timestamp_pc_monotonic_ns'),
      ax: value('ax_raw'),
      ay: value('ay_raw'),
      az: value('az_raw'),
      gx: value('gx_raw'),
      gy: value('gy_raw'),
      gz: value('gz_raw'),
    );
  }
}

class DesktopAcquisitionState {
  const DesktopAcquisitionState({
    this.connected = false,
    this.connecting = false,
    this.scanning = false,
    this.status = const {},
    this.devices = const [],
    this.sessions = const [],
    this.lastPreviewBySide = const {},
    this.previewHistoryBySide = const {},
    this.lastEvent,
    this.lastRecordingResult,
    this.error,
  });

  final bool connected;
  final bool connecting;
  final bool scanning;
  final Map<String, dynamic> status;
  final List<Map<String, dynamic>> devices;
  final List<Map<String, dynamic>> sessions;
  final Map<String, Map<String, dynamic>> lastPreviewBySide;
  final Map<String, List<DesktopPreviewSample>> previewHistoryBySide;
  final DesktopDaemonEvent? lastEvent;
  final Map<String, dynamic>? lastRecordingResult;
  final String? error;

  bool get recording => status['recording'] == true;

  DesktopAcquisitionState copyWith({
    bool? connected,
    bool? connecting,
    bool? scanning,
    Map<String, dynamic>? status,
    List<Map<String, dynamic>>? devices,
    List<Map<String, dynamic>>? sessions,
    Map<String, Map<String, dynamic>>? lastPreviewBySide,
    Map<String, List<DesktopPreviewSample>>? previewHistoryBySide,
    DesktopDaemonEvent? lastEvent,
    Object? lastRecordingResult = _sentinel,
    Object? error = _sentinel,
  }) => DesktopAcquisitionState(
    connected: connected ?? this.connected,
    connecting: connecting ?? this.connecting,
    scanning: scanning ?? this.scanning,
    status: status ?? this.status,
    devices: devices ?? this.devices,
    sessions: sessions ?? this.sessions,
    lastPreviewBySide: lastPreviewBySide ?? this.lastPreviewBySide,
    previewHistoryBySide: previewHistoryBySide ?? this.previewHistoryBySide,
    lastEvent: lastEvent ?? this.lastEvent,
    lastRecordingResult: identical(lastRecordingResult, _sentinel)
        ? this.lastRecordingResult
        : lastRecordingResult as Map<String, dynamic>?,
    error: identical(error, _sentinel) ? this.error : error as String?,
  );

  static const Object _sentinel = Object();
}

final desktopDaemonClientFactoryProvider =
    Provider<Future<DesktopDaemonClient> Function()>((ref) {
      return () => DesktopDaemonClient.connect();
    });

class DesktopAcquisitionNotifier extends Notifier<DesktopAcquisitionState> {
  static const int previewHistoryCap = 240;

  DesktopDaemonClient? _client;
  StreamSubscription<DesktopDaemonEvent>? _events;
  Timer? _statusTimer;
  bool _refreshing = false;

  @override
  DesktopAcquisitionState build() {
    ref.onDispose(() {
      _statusTimer?.cancel();
      _events?.cancel();
      _client?.close();
    });
    return const DesktopAcquisitionState();
  }

  Future<void> connect() async {
    if (!Platform.isWindows) {
      state = state.copyWith(
        error: 'The PC acquisition daemon is only used on Windows.',
      );
      return;
    }
    if (_client != null && !_client!.isClosed) return;
    state = state.copyWith(connecting: true, error: null);
    try {
      final client = await ref.read(desktopDaemonClientFactoryProvider)();
      _client = client;
      _events = client.events.listen(
        _handleEvent,
        onError: (Object error) {
          if (ref.mounted) {
            state = state.copyWith(connected: false, error: '$error');
          }
        },
        onDone: () {
          if (ref.mounted) state = state.copyWith(connected: false);
        },
      );
      final status = await client.request('status');
      if (ref.mounted) {
        state = state.copyWith(
          connected: true,
          connecting: false,
          status: status,
          error: null,
        );
        _startStatusPolling();
      }
    } on Object catch (error) {
      await _events?.cancel();
      _events = null;
      await _client?.close();
      _client = null;
      if (ref.mounted) {
        state = state.copyWith(
          connected: false,
          connecting: false,
          error: '$error',
        );
      }
    }
  }

  void _startStatusPolling() {
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(refreshStatus());
    });
  }

  Future<Map<String, dynamic>> command(
    String type, [
    Map<String, dynamic> payload = const {},
    Duration timeout = const Duration(seconds: 15),
  ]) async {
    final client = _client;
    if (client == null || client.isClosed) {
      throw StateError('desktop acquisition daemon is not connected');
    }
    final result = await client.request(type, payload, timeout);
    if (type == 'status' && ref.mounted) {
      state = state.copyWith(status: result);
    }
    return result;
  }

  Future<void> refreshStatus() async {
    if (_refreshing || !state.connected) return;
    _refreshing = true;
    try {
      final status = await command('status');
      if (ref.mounted) state = state.copyWith(status: status, error: null);
    } on Object catch (error) {
      if (ref.mounted) state = state.copyWith(error: '$error');
    } finally {
      _refreshing = false;
    }
  }

  Future<void> scan({double timeoutSeconds = 5}) async {
    state = state.copyWith(scanning: true, error: null);
    try {
      final result = await command('scan', {
        'timeout_s': timeoutSeconds,
      }, const Duration(seconds: 15));
      final raw = result['devices'];
      final devices = raw is List
          ? raw
                .whereType<Map<String, dynamic>>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList(growable: false)
          : <Map<String, dynamic>>[];
      if (ref.mounted) {
        state = state.copyWith(scanning: false, devices: devices, error: null);
      }
    } on Object catch (error) {
      if (ref.mounted) {
        state = state.copyWith(scanning: false, error: '$error');
      }
    }
  }

  Future<Map<String, dynamic>> connectDevice(String deviceId) async {
    final result = await command('connect', {'device_id': deviceId});
    await refreshStatus();
    return result;
  }

  Future<void> disconnectSide(String side) async {
    await command('disconnect', {'side': side});
    await refreshStatus();
  }

  Future<void> configureSide(
    String side, {
    int? sampleRateHz,
    int? accelRange,
    int? gyroRange,
  }) async {
    final payload = <String, dynamic>{'side': side};
    if (sampleRateHz != null) payload['sample_rate_hz'] = sampleRateHz;
    if (accelRange != null) payload['accel_range'] = accelRange;
    if (gyroRange != null) payload['gyro_range'] = gyroRange;
    await command('configure', payload);
    await refreshStatus();
  }

  Future<Map<String, dynamic>> startRecord(
    Map<String, dynamic> metadata,
  ) async {
    state = state.copyWith(error: null, lastRecordingResult: null);
    final configuredRate = (metadata['sample_rate_hz'] as num?)?.toInt();
    if (configuredRate != null) {
      final rawBoards = state.status['boards'];
      if (rawBoards is Map) {
        for (final entry in rawBoards.entries) {
          if (entry.value is Map && (entry.value as Map)['connected'] == true) {
            await command('configure', {
              'side': '${entry.key}',
              'sample_rate_hz': configuredRate,
            });
          }
        }
      }
    }
    final result = await command(
      'start_record',
      metadata,
      const Duration(seconds: 45),
    );
    await refreshStatus();
    return result;
  }

  Future<Map<String, dynamic>> endRecord() async {
    final result = await command(
      'end_record',
      const {},
      const Duration(seconds: 45),
    );
    if (ref.mounted) state = state.copyWith(lastRecordingResult: result);
    await refreshStatus();
    await loadSessions();
    return result;
  }

  Future<void> loadSessions() async {
    if (!state.connected) return;
    try {
      final result = await command('list_sessions');
      final raw = result['sessions'];
      final sessions = raw is List
          ? raw
                .whereType<Map<String, dynamic>>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList(growable: false)
          : <Map<String, dynamic>>[];
      if (ref.mounted) state = state.copyWith(sessions: sessions, error: null);
    } on Object catch (error) {
      if (ref.mounted) state = state.copyWith(error: '$error');
    }
  }

  Future<String> exportSession(String sessionId, {String? outputPath}) async {
    final payload = <String, dynamic>{'session_id': sessionId};
    if (outputPath != null) payload['output_path'] = outputPath;
    final result = await command(
      'export_session',
      payload,
      const Duration(seconds: 45),
    );
    return '${result['output_path'] ?? ''}';
  }

  Future<String> exportDiagnosticReport({String? outputPath}) async {
    final payload = <String, dynamic>{};
    if (outputPath != null) payload['output_path'] = outputPath;
    final result = await command('diagnostic_report', payload);
    return '${result['output_path'] ?? ''}';
  }

  Future<String> recover(String fileName) async {
    final result = await command('recover', {'file_name': fileName});
    await refreshStatus();
    return '${result['recovered'] ?? ''}';
  }

  void _handleEvent(DesktopDaemonEvent event) {
    if (!ref.mounted) return;
    if (event.type == 'sample_preview') {
      final side = '${event.payload['side'] ?? ''}';
      if (side.isNotEmpty) {
        final sample = DesktopPreviewSample.fromPayload(event.payload);
        final previous = state.previewHistoryBySide[side] ?? const [];
        final next = <DesktopPreviewSample>[...previous, sample];
        if (next.length > previewHistoryCap) {
          next.removeRange(0, next.length - previewHistoryCap);
        }
        state = state.copyWith(
          lastPreviewBySide: {
            ...state.lastPreviewBySide,
            side: Map<String, dynamic>.from(event.payload),
          },
          previewHistoryBySide: {
            ...state.previewHistoryBySide,
            side: List<DesktopPreviewSample>.unmodifiable(next),
          },
          lastEvent: event,
        );
        return;
      }
    }

    state = state.copyWith(lastEvent: event);
    if (event.type == 'error') {
      state = state.copyWith(
        error: '${event.payload['message'] ?? event.payload}',
      );
    }
    if (event.type == 'connection_state' ||
        event.type == 'recording_state' ||
        event.type == 'sync_status') {
      unawaited(refreshStatus());
    }
  }

  Future<void> disconnect() async {
    _statusTimer?.cancel();
    _statusTimer = null;
    await _events?.cancel();
    _events = null;
    await _client?.close();
    _client = null;
    if (ref.mounted) state = const DesktopAcquisitionState();
  }
}

final desktopAcquisitionProvider =
    NotifierProvider<DesktopAcquisitionNotifier, DesktopAcquisitionState>(
      DesktopAcquisitionNotifier.new,
    );
