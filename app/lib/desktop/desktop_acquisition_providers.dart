import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wheelathlete/desktop/daemon_client.dart';

class DesktopAcquisitionState {
  const DesktopAcquisitionState({
    this.connected = false,
    this.status = const {},
    this.lastPreviewBySide = const {},
    this.lastEvent,
    this.error,
  });

  final bool connected;
  final Map<String, dynamic> status;
  final Map<String, Map<String, dynamic>> lastPreviewBySide;
  final DesktopDaemonEvent? lastEvent;
  final String? error;

  DesktopAcquisitionState copyWith({
    bool? connected,
    Map<String, dynamic>? status,
    Map<String, Map<String, dynamic>>? lastPreviewBySide,
    DesktopDaemonEvent? lastEvent,
    Object? error = _sentinel,
  }) => DesktopAcquisitionState(
    connected: connected ?? this.connected,
    status: status ?? this.status,
    lastPreviewBySide: lastPreviewBySide ?? this.lastPreviewBySide,
    lastEvent: lastEvent ?? this.lastEvent,
    error: identical(error, _sentinel) ? this.error : error as String?,
  );

  static const Object _sentinel = Object();
}

final desktopDaemonClientFactoryProvider =
    Provider<Future<DesktopDaemonClient> Function()>((ref) {
      return () => DesktopDaemonClient.connect();
    });

class DesktopAcquisitionNotifier extends Notifier<DesktopAcquisitionState> {
  DesktopDaemonClient? _client;
  StreamSubscription<DesktopDaemonEvent>? _events;

  @override
  DesktopAcquisitionState build() {
    ref.onDispose(() {
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
    state = state.copyWith(error: null);
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
      );
      final status = await client.request('status');
      if (ref.mounted) {
        state = state.copyWith(connected: true, status: status, error: null);
      }
    } on Object catch (error) {
      if (ref.mounted) {
        state = state.copyWith(connected: false, error: '$error');
      }
    }
  }

  Future<Map<String, dynamic>> command(
    String type, [
    Map<String, dynamic> payload = const {},
  ]) async {
    final client = _client;
    if (client == null || client.isClosed) {
      throw StateError('desktop acquisition daemon is not connected');
    }
    final result = await client.request(type, payload);
    if (type == 'status' && ref.mounted) {
      state = state.copyWith(status: result);
    }
    return result;
  }

  Future<void> refreshStatus() async {
    try {
      final status = await command('status');
      if (ref.mounted) state = state.copyWith(status: status, error: null);
    } on Object catch (error) {
      if (ref.mounted) state = state.copyWith(error: '$error');
    }
  }

  void _handleEvent(DesktopDaemonEvent event) {
    if (!ref.mounted) return;
    if (event.type == 'sample_preview') {
      final side = '${event.payload['side'] ?? ''}';
      if (side.isNotEmpty) {
        state = state.copyWith(
          lastPreviewBySide: {
            ...state.lastPreviewBySide,
            side: Map<String, dynamic>.from(event.payload),
          },
          lastEvent: event,
        );
        return;
      }
    }
    state = state.copyWith(lastEvent: event);
    if (event.type == 'error') {
      state = state.copyWith(error: '${event.payload['message'] ?? event.payload}');
    }
  }

  Future<void> disconnect() async {
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
