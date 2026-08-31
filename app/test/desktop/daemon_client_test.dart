import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/desktop/daemon_client.dart';

Future<Map<String, dynamic>> _readJson(StreamIterator<String> lines) async {
  expect(await lines.moveNext(), isTrue);
  return Map<String, dynamic>.from(jsonDecode(lines.current) as Map);
}

void main() {
  test('desktop daemon client handshakes, correlates responses, and emits preview', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final serverTask = server.first.then((socket) async {
      final lines = StreamIterator<String>(
        socket
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter()),
      );
      final hello = await _readJson(lines);
      expect(hello['type'], 'hello');
      socket.writeln(
        jsonEncode({
          'protocol_version': desktopProtocolVersion,
          'type': 'hello_ack',
          'request_id': hello['request_id'],
          'payload': {
            'server': 'test',
            'protocol_version': desktopProtocolVersion,
          },
        }),
      );
      await socket.flush();

      final status = await _readJson(lines);
      socket.writeln(
        jsonEncode({
          'protocol_version': desktopProtocolVersion,
          'type': 'sample_preview',
          'payload': {'side': 'L', 'seq': 9},
        }),
      );
      socket.writeln(
        jsonEncode({
          'protocol_version': desktopProtocolVersion,
          'type': 'response',
          'request_id': status['request_id'],
          'payload': {
            'ok': true,
            'result': {'recording': false},
          },
        }),
      );
      await socket.flush();
      await lines.cancel();
      socket.destroy();
    });

    final client = await DesktopDaemonClient.connect(port: server.port);
    final eventFuture = client.events.first;
    final status = await client.request('status');
    expect(status['recording'], isFalse);
    final event = await eventFuture;
    expect(event.type, 'sample_preview');
    expect(event.payload['side'], 'L');
    expect(event.payload['seq'], 9);

    await client.close();
    await serverTask;
    await server.close();
  });

  test('desktop daemon client rejects protocol mismatch', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final serverTask = server.first.then((socket) async {
      final lines = StreamIterator<String>(
        socket
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter()),
      );
      final hello = await _readJson(lines);
      socket.writeln(
        jsonEncode({
          'protocol_version': desktopProtocolVersion + 1,
          'type': 'hello_ack',
          'request_id': hello['request_id'],
          'payload': {
            'server': 'wrong-version',
            'protocol_version': desktopProtocolVersion + 1,
          },
        }),
      );
      await socket.flush();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      socket.destroy();
    });

    await expectLater(
      DesktopDaemonClient.connect(port: server.port),
      throwsA(isA<DesktopDaemonProtocolException>()),
    );
    await serverTask;
    await server.close();
  });
}
