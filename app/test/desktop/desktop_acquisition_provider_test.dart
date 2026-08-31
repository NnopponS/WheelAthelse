import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/desktop/daemon_client.dart';
import 'package:wheelathlete/desktop/desktop_acquisition_providers.dart';

Future<Map<String, dynamic>> _nextJson(StreamIterator<String> lines) async {
  expect(await lines.moveNext(), isTrue);
  return Map<String, dynamic>.from(jsonDecode(lines.current) as Map);
}

void _sendResponse(
  Socket socket,
  Map<String, dynamic> request,
  Map<String, dynamic> result,
) {
  socket.writeln(
    jsonEncode({
      'protocol_version': desktopProtocolVersion,
      'type': 'response',
      'request_id': request['request_id'],
      'payload': {'ok': true, 'result': result},
    }),
  );
}

void main() {
  test(
    'startRecord configures every connected wheel to the requested rate first',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final commands = <Map<String, dynamic>>[];
      final serverTask = server.first.then((socket) async {
        final lines = StreamIterator<String>(
          socket
              .cast<List<int>>()
              .transform(utf8.decoder)
              .transform(const LineSplitter()),
        );

        final hello = await _nextJson(lines);
        socket.writeln(
          jsonEncode({
            'protocol_version': desktopProtocolVersion,
            'type': 'hello_ack',
            'request_id': hello['request_id'],
            'payload': {
              'server': 'provider-test',
              'protocol_version': desktopProtocolVersion,
            },
          }),
        );
        await socket.flush();

        for (var index = 0; index < 5; index++) {
          final request = await _nextJson(lines);
          commands.add(request);
          switch (request['type']) {
            case 'status':
              _sendResponse(socket, request, {
                'recording': false,
                'boards': {
                  'L': {'connected': true},
                  'R': {'connected': true},
                },
              });
            case 'configure':
              _sendResponse(socket, request, {
                'side': (request['payload'] as Map)['side'],
                'configured': true,
              });
            case 'start_record':
              _sendResponse(socket, request, {
                'session_id': 'session-test',
                'journal_path': 'session-test.open',
              });
            default:
              fail('unexpected command ${request['type']}');
          }
          await socket.flush();
        }
        await lines.cancel();
        socket.destroy();
      });

      final container = ProviderContainer(
        overrides: [
          desktopDaemonClientFactoryProvider.overrideWithValue(
            () => DesktopDaemonClient.connect(port: server.port),
          ),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(desktopAcquisitionProvider.notifier);
      await notifier.connect();
      await notifier.startRecord({
        'athlete': 'Athlete A',
        'topic': 'Sprint',
        'trial_number': 1,
        'sample_rate_hz': 200,
      });

      await serverTask;
      await server.close();

      final commandTypes = commands.map((item) => item['type']).toList();
      expect(commandTypes, [
        'status',
        'configure',
        'configure',
        'start_record',
        'status',
      ]);
      final configure = commands
          .where((item) => item['type'] == 'configure')
          .toList();
      expect(
        configure.map((item) => (item['payload'] as Map)['side']).toSet(),
        {'L', 'R'},
      );
      expect(
        configure
            .map((item) => (item['payload'] as Map)['sample_rate_hz'])
            .toSet(),
        {200},
      );
    },
  );
}
