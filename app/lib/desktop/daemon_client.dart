import 'dart:async';
import 'dart:convert';
import 'dart:io';

const int desktopProtocolVersion = 1;
const int desktopMaxMessageBytes = 64 * 1024;

class DesktopDaemonProtocolException implements Exception {
  const DesktopDaemonProtocolException(this.message);
  final String message;

  @override
  String toString() => 'DesktopDaemonProtocolException: $message';
}

class DesktopDaemonCommandException implements Exception {
  const DesktopDaemonCommandException(this.code, this.message);
  final String code;
  final String message;

  @override
  String toString() => 'DesktopDaemonCommandException($code): $message';
}

class DesktopDaemonEvent {
  const DesktopDaemonEvent({required this.type, required this.payload});
  final String type;
  final Map<String, dynamic> payload;
}

class _PendingRequest {
  _PendingRequest(this.completer, this.timer);
  final Completer<Map<String, dynamic>> completer;
  final Timer timer;
}

/// Versioned localhost NDJSON client for the Windows acquisition daemon.
///
/// The daemon owns raw IMU acquisition and storage. This client receives only
/// responses, telemetry, health and throttled preview events.
class DesktopDaemonClient {
  DesktopDaemonClient._(this._socket);

  final Socket _socket;
  final Map<String, _PendingRequest> _pending = {};
  final StreamController<DesktopDaemonEvent> _events =
      StreamController<DesktopDaemonEvent>.broadcast();
  StreamSubscription<String>? _lineSubscription;
  int _nextRequest = 1;
  bool _closed = false;

  Stream<DesktopDaemonEvent> get events => _events.stream;
  bool get isClosed => _closed;

  static Future<DesktopDaemonClient> connect({
    String host = '127.0.0.1',
    int port = 8765,
    Duration timeout = const Duration(seconds: 3),
  }) async {
    if (host != '127.0.0.1' && host != 'localhost') {
      throw ArgumentError.value(host, 'host', 'daemon must use localhost');
    }
    final socket = await Socket.connect(host, port, timeout: timeout);
    final client = DesktopDaemonClient._(socket);
    client._listen();
    final hello = await client._request(
      'hello',
      const {},
      timeout: timeout,
      allowHelloAck: true,
    );
    if (hello['protocol_version'] != desktopProtocolVersion) {
      await client.close();
      throw DesktopDaemonProtocolException(
        'daemon protocol ${hello['protocol_version']} does not match '
        '$desktopProtocolVersion',
      );
    }
    return client;
  }

  Future<Map<String, dynamic>> request(
    String type, [
    Map<String, dynamic> payload = const {},
    Duration timeout = const Duration(seconds: 15),
  ]) => _request(type, payload, timeout: timeout);

  Future<Map<String, dynamic>> _request(
    String type,
    Map<String, dynamic> payload, {
    required Duration timeout,
    bool allowHelloAck = false,
  }) async {
    if (_closed) throw StateError('daemon client is closed');
    final requestId = 'dart-${_nextRequest++}';
    final completer = Completer<Map<String, dynamic>>();
    final timer = Timer(timeout, () {
      final pending = _pending.remove(requestId);
      if (pending != null && !pending.completer.isCompleted) {
        pending.completer.completeError(
          TimeoutException('daemon request $type timed out', timeout),
        );
      }
    });
    _pending[requestId] = _PendingRequest(completer, timer);
    final message = <String, dynamic>{
      'protocol_version': desktopProtocolVersion,
      'type': type,
      'request_id': requestId,
      'payload': payload,
    };
    final encoded = '${jsonEncode(message)}\n';
    if (utf8.encode(encoded).length > desktopMaxMessageBytes) {
      _pending.remove(requestId)?.timer.cancel();
      throw const DesktopDaemonProtocolException(
        'outgoing message exceeds maximum size',
      );
    }
    _socket.write(encoded);
    await _socket.flush();
    final response = await completer.future;
    final responseType = response['type'];
    if (allowHelloAck && responseType == 'hello_ack') {
      return _objectPayload(response);
    }
    if (responseType == 'error') {
      final error = _objectPayload(response);
      throw DesktopDaemonCommandException(
        '${error['code'] ?? 'error'}',
        '${error['message'] ?? 'daemon command failed'}',
      );
    }
    if (responseType != 'response') {
      throw DesktopDaemonProtocolException(
        'unexpected response type $responseType for $type',
      );
    }
    final wrapper = _objectPayload(response);
    if (wrapper['ok'] != true || wrapper['result'] is! Map) {
      throw DesktopDaemonProtocolException('malformed response for $type');
    }
    return Map<String, dynamic>.from(wrapper['result'] as Map);
  }

  void _listen() {
    _lineSubscription = _socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          _handleLine,
          onError: _failAll,
          onDone: () => _failAll(
            const DesktopDaemonProtocolException('daemon connection closed'),
          ),
        );
  }

  void _handleLine(String line) {
    if (utf8.encode(line).length + 1 > desktopMaxMessageBytes) {
      _failAll(
        const DesktopDaemonProtocolException('incoming message is too large'),
      );
      return;
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException catch (error) {
      _failAll(DesktopDaemonProtocolException('invalid daemon JSON: $error'));
      return;
    }
    if (decoded is! Map<String, dynamic>) {
      _failAll(
        const DesktopDaemonProtocolException('daemon message is not an object'),
      );
      return;
    }
    if (decoded['protocol_version'] != desktopProtocolVersion) {
      _failAll(
        DesktopDaemonProtocolException(
          'unexpected protocol_version ${decoded['protocol_version']}',
        ),
      );
      return;
    }
    final type = decoded['type'];
    if (type is! String || type.isEmpty) {
      _failAll(
        const DesktopDaemonProtocolException('daemon message type is invalid'),
      );
      return;
    }
    final requestId = decoded['request_id'];
    if (requestId is String) {
      final pending = _pending.remove(requestId);
      if (pending != null) {
        pending.timer.cancel();
        if (!pending.completer.isCompleted) {
          pending.completer.complete(decoded);
        }
        return;
      }
    }
    try {
      _events.add(
        DesktopDaemonEvent(type: type, payload: _objectPayload(decoded)),
      );
    } on Object catch (error, stackTrace) {
      _events.addError(error, stackTrace);
    }
  }

  static Map<String, dynamic> _objectPayload(Map<String, dynamic> message) {
    final payload = message['payload'];
    if (payload is! Map) {
      throw const DesktopDaemonProtocolException(
        'daemon payload is not an object',
      );
    }
    return Map<String, dynamic>.from(payload);
  }

  void _failAll(Object error, [StackTrace? stackTrace]) {
    if (_closed) return;
    for (final pending in _pending.values) {
      pending.timer.cancel();
      if (!pending.completer.isCompleted) {
        pending.completer.completeError(error, stackTrace);
      }
    }
    _pending.clear();
    if (!_events.isClosed) _events.addError(error, stackTrace);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final pending in _pending.values) {
      pending.timer.cancel();
      if (!pending.completer.isCompleted) {
        pending.completer.completeError(
          const DesktopDaemonProtocolException('daemon client closed'),
        );
      }
    }
    _pending.clear();
    await _lineSubscription?.cancel();
    _socket.destroy();
    await _events.close();
  }
}

/// Development/source launcher. Production packaging can replace [executable]
/// and [arguments] with a bundled daemon executable without changing IPC.
class DesktopDaemonProcess {
  DesktopDaemonProcess._(this.process);
  final Process process;

  static Future<DesktopDaemonProcess> launch({
    String executable = 'python',
    List<String>? arguments,
    String? workingDirectory,
  }) async {
    final process = await Process.start(
      executable,
      arguments ?? const ['-m', 'tools.pc_acquisition.daemon'],
      workingDirectory: workingDirectory,
      mode: ProcessStartMode.detachedWithStdio,
    );
    return DesktopDaemonProcess._(process);
  }

  void stop() => process.kill();
}
