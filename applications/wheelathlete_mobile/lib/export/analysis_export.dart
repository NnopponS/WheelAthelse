import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:wheelathlete/model/analysis_contract.dart';

/// Numeric full-session timeline; null numeric cells are empty, flags are JSON.
String analysisCsv(KinematicAnalysis analysis) {
  final text = StringBuffer(
    '${[...analysisFields, 'quality_flags'].join(',')}\r\n',
  );
  for (final sample in analysis.samples) {
    final numeric = analysisFields
        .map((field) => sample[field]?.toString() ?? '')
        .join(',');
    final flags = jsonEncode(sample.qualityFlags).replaceAll('"', '""');
    text.write('$numeric,"$flags"\r\n');
  }
  return text.toString();
}

// Keep full-session serialization, hashing and statistics off the UI isolate.
// Metadata can be encoded directly; toJson() would copy every sample again.
(List<int>, String, String) _encodeAnalysisExport(
  (KinematicAnalysis, double, double) request,
) {
  final (analysis, start, stop) = request;
  final statistics = analysis.windowStatistics(start, stop);
  final csv = utf8.encode(analysisCsv(analysis));
  final hash = sha256.convert(csv).toString();
  final metadata = {
    'schema_version': 1,
    'export_type': 'wheelathlete_derived_analysis',
    'metadata': analysis.metadata,
    'columns': [...analysisFields, 'quality_flags'],
    'row_count': analysis.samples.length,
    'null_encoding': 'empty CSV numeric cell; JSON null',
    'timeline_sha256': hash,
    'selected_window': {
      'requested_start_s': start,
      'requested_stop_s': stop,
      ...statistics,
    },
    'export_scope':
        'full-resolution full-session timeline; selected window is metadata only; no pose reset',
  };
  return (csv, const JsonEncoder.withIndent('  ').convert(metadata), hash);
}

/// Creates a unique child directory; existing recordings/exports are never
/// replaced. COMPLETE is written last; absence means incomplete IO.
Future<Directory> saveAnalysis(
  KinematicAnalysis analysis,
  Directory parent, {
  double? startS,
  double? stopS,
}) async {
  if (!await parent.exists()) {
    throw const FileSystemException('Choose an existing directory');
  }
  final start = startS ?? analysis.samples.first.timeS;
  final stop = stopS ?? analysis.samples.last.timeS;
  if (!start.isFinite || !stop.isFinite || stop < start) {
    throw const FormatException('Invalid export time window');
  }
  final (csv, metadata, hash) = await compute(_encodeAnalysisExport, (
    analysis,
    start,
    stop,
  ));
  final session = (analysis.metadata['session_id'] ?? 'session')
      .toString()
      .replaceAll(RegExp('[^A-Za-z0-9_-]'), '_');
  final prefix = session.length > 64 ? session.substring(0, 64) : session;
  final out = await parent.createTemp('WheelAthlete_analysis_${prefix}_');
  try {
    await File('${out.path}/timeline.csv').writeAsBytes(csv, flush: true);
    await File(
      '${out.path}/metadata.json',
    ).writeAsString(metadata, flush: true);
    await File('${out.path}/COMPLETE').writeAsString('$hash\n', flush: true);
    return out;
  } on FileSystemException catch (error) {
    throw FileSystemException(
      'Analysis export incomplete; no existing file replaced. ${error.message}',
      out.path,
    );
  }
}
