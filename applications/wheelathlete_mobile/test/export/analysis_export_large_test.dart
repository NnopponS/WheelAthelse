import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/export/analysis_export.dart';
import 'package:wheelathlete/model/analysis_contract.dart';

void main() {
  test(
    'long recording exports every source row through background serialization',
    () async {
      const count = 8000;
      final times = List.generate(count, (i) => 2.02 + i * 0.05);
      final analysis = buildKinematicAnalysis(
        times: times,
        xy: times.map((time) => [time - times.first, 0.0]).toList(),
        flags: List.generate(count, (_) => <String>[]),
        signedSpeed: List.filled(count, 1.0),
        yaw: List.filled(count, 0.0),
        yawRate: List.filled(count, 0.0),
        metadata: const {'session_id': 'synthetic-long-export'},
      );
      final parent = await Directory.systemTemp.createTemp(
        'wheelathlete_long_export_',
      );
      addTearDown(() => parent.delete(recursive: true));
      final out = await saveAnalysis(
        analysis,
        parent,
        startS: times[200],
        stopS: times[400],
      );
      final bytes = await File('${out.path}/timeline.csv').readAsBytes();
      final rows = const LineSplitter().convert(utf8.decode(bytes));
      final meta =
          jsonDecode(await File('${out.path}/metadata.json').readAsString())
              as Map<String, dynamic>;
      expect(rows.length, count + 1);
      expect(double.parse(rows.last.split(',').first), times.last);
      expect(meta['row_count'], count);
      expect((meta['selected_window'] as Map)['samples'], 201);
      expect(meta['timeline_sha256'], sha256.convert(bytes).toString());
      expect(
        await File('${out.path}/COMPLETE').readAsString(),
        '${meta['timeline_sha256']}\n',
      );
      expect(analysis.samples[200].xM, closeTo(10.0, 1e-9));
    },
  );
}
