import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/model/analysis_contract.dart';
import 'package:wheelathlete/export/analysis_export.dart';

KinematicAnalysis example() {
  final t = List.generate(40, (i) => i * 0.05);
  return buildKinematicAnalysis(
    times: t,
    xy: t.map((v) => [v, 0.0]).toList(),
    flags: List.generate(40, (_) => <String>[]),
    signedSpeed: List.filled(40, 1.0),
    yaw: List.filled(40, 0.0),
    yawRate: List.filled(40, 0.0),
    metadata: {'session_id': '../unsafe/name'},
  );
}

void main() {
  test(
    'full-resolution CSV encodes missingness and flags without invented zero',
    () {
      final a = example();
      final rows = const LineSplitter().convert(analysisCsv(a));
      expect(rows.length, 41);
      expect(rows.first, contains('yaw_rate_radps'));
      expect(rows[1], contains('derivative_support_unavailable'));
      final columns = rows[1].split(',');
      expect(columns[5], isEmpty);
      expect(columns[3], '1.0');
    },
  );
  test(
    'unique export contains complete full timeline and selected-window metadata',
    () async {
      final parent = await Directory.systemTemp.createTemp(
        'wheelathlete_export_test_',
      );
      addTearDown(() => parent.delete(recursive: true));
      final original = File('${parent.path}/original.csv');
      await original.writeAsString('do not modify');
      final a = example();
      final before = jsonEncode(a.toJson());
      final first = await saveAnalysis(a, parent, startS: 0.25, stopS: 0.75);
      final second = await saveAnalysis(a, parent);
      expect(first.path, isNot(second.path));
      final bytes = await File('${first.path}/timeline.csv').readAsBytes();
      final meta =
          jsonDecode(await File('${first.path}/metadata.json').readAsString())
              as Map;
      expect(meta['row_count'], 40);
      expect((meta['selected_window'] as Map)['samples'], 11);
      expect(meta['timeline_sha256'], sha256.convert(bytes).toString());
      expect(await File('${first.path}/COMPLETE').exists(), isTrue);
      expect(await original.readAsString(), 'do not modify');
      expect(jsonEncode(a.toJson()), before);
    },
  );
  test('invalid window fails before creating a new output', () async {
    final parent = await Directory.systemTemp.createTemp(
      'wheelathlete_bad_window_',
    );
    addTearDown(() => parent.delete(recursive: true));
    await expectLater(
      saveAnalysis(example(), parent, startS: 2.0, stopS: 1.0),
      throwsFormatException,
    );
    expect(await parent.list().toList(), isEmpty);
  });
}
