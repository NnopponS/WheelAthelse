import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wheelathlete/export/csv_exporter.dart';
import 'package:wheelathlete/export/excel_exporter.dart';
import 'package:wheelathlete/export/export_actions.dart';
import 'package:wheelathlete/export/resampler.dart';
import 'package:wheelathlete/state/ble_providers.dart';

/// Export state surfaced to the UI.
class ExportState {
  const ExportState({
    this.isExporting = false,
    this.lastExportedPaths = const [],
    this.error,
  });

  final bool isExporting;
  final List<String> lastExportedPaths;
  final String? error;
}

/// Manages exporting sessions to CSV (with optional resampling) and sharing
/// files via `share_plus`.
///
/// Export writes a CSV file to the storage repository's trial folder using
/// [CsvExporter] for streaming writes. Optional resampling via [Resampler]
/// aligns both wheels to a common time grid.
class ExportNotifier extends Notifier<ExportState> implements ExportOperations {
  @override
  ExportState build() => const ExportState();

  /// Exports a single session to CSV. If [resample] is true, samples are
  /// resampled to [gridIntervalMs] before writing. Returns the file path.
  ///
  /// Throws [StateError] if the session has no samples (empty recording).
  Future<String> exportSession({
    required String topic,
    required int trialNumber,
    required String sessionId,
    bool resample = false,
    double gridIntervalMs = 10,
  }) async {
    state = const ExportState(isExporting: true);

    try {
      final storage = ref.read(storageRepositoryProvider);
      final meta = await storage.readSessionMeta(topic, trialNumber, sessionId);
      if (meta == null) {
        throw StateError('Session not found: $topic/trial_$trialNumber/$sessionId');
      }

      var samples = await storage.readSamples(topic, trialNumber, sessionId);
      if (samples.isEmpty) {
        throw StateError(
          'Session "$sessionId" has no data. This may happen if the '
          'recording was made before the scheduled-start fix. Please '
          'record a new session.',
        );
      }
      if (resample) {
        samples = Resampler.resample(samples, gridIntervalMs: gridIntervalMs);
      }

      // Write XLSX to storage (file-based or in-memory).
      final xlsxPath = await storage.getSessionXlsxPath(topic, trialNumber, sessionId);
      final xlsxBytes = ExcelExporter.toXlsxBytes(samples);
      await storage.writeSessionXlsx(topic, trialNumber, sessionId, xlsxBytes);

      state = ExportState(
        lastExportedPaths: [xlsxPath],
      );
      return xlsxPath;
    } on Object catch (e) {
      state = ExportState(error: 'Export failed: $e');
      rethrow;
    }
  }

  /// Exports all sessions in a trial. Returns the list of file paths.
  Future<List<String>> exportTrial({
    required String topic,
    required int trialNumber,
    bool resample = false,
    double gridIntervalMs = 10,
  }) async {
    final storage = ref.read(storageRepositoryProvider);
    final sessions = await storage.listSessions(topic, trialNumber);
    final paths = <String>[];
    for (final meta in sessions) {
      final path = await exportSession(
        topic: topic,
        trialNumber: trialNumber,
        sessionId: meta.sessionId,
        resample: resample,
        gridIntervalMs: gridIntervalMs,
      );
      paths.add(path);
    }
    return paths;
  }

  /// Exports all sessions in all trials of a topic.
  Future<List<String>> exportTopic({
    required String topic,
    bool resample = false,
    double gridIntervalMs = 10,
  }) async {
    final storage = ref.read(storageRepositoryProvider);
    final trials = await storage.listTrials(topic);
    final paths = <String>[];
    for (final trial in trials) {
      final trialPaths = await exportTrial(
        topic: topic,
        trialNumber: trial,
        resample: resample,
        gridIntervalMs: gridIntervalMs,
      );
      paths.addAll(trialPaths);
    }
    return paths;
  }

  /// Shares a single session CSV file via `share_plus`.
  @override
  Future<void> shareSession({
    required String topic,
    required int trialNumber,
    required String sessionId,
  }) async {
    final path = await exportSession(
      topic: topic,
      trialNumber: trialNumber,
      sessionId: sessionId,
    );
    await SharePlus.instance.share(
      ShareParams(files: [XFile(path)], text: 'WheelAthlete session $sessionId'),
    );
  }

  /// Shares all session CSVs in a trial.
  @override
  Future<void> shareTrial({
    required String topic,
    required int trialNumber,
  }) async {
    final paths = await exportTrial(topic: topic, trialNumber: trialNumber);
    if (paths.isEmpty) return;
    await SharePlus.instance.share(
      ShareParams(
        files: paths.map((p) => XFile(p)).toList(),
        text: 'WheelAthlete trial $trialNumber',
      ),
    );
  }

  /// Shares all session CSVs in a topic.
  @override
  Future<void> shareTopic({required String topic}) async {
    final paths = await exportTopic(topic: topic);
    if (paths.isEmpty) return;
    await SharePlus.instance.share(
      ShareParams(
        files: paths.map((p) => XFile(p)).toList(),
        text: 'WheelAthlete topic $topic',
      ),
    );
  }

  /// Clears the export state.
  void clearError() {
    state = const ExportState();
  }
}

final exportProvider = NotifierProvider<ExportNotifier, ExportState>(
  ExportNotifier.new,
);

/// Production [DirectoryPicker] backed by file_picker's `getDirectoryPath`.
// coverage:ignore-start
Future<String?> pickDirectory() async {
  return FilePicker.getDirectoryPath(
    dialogTitle: 'Choose where to save Excel files',
  );
}
// coverage:ignore-end

/// Production [FileSink] that writes [bytes] to the file at [path].
// coverage:ignore-start
Future<void> writeCsvFile(String path, List<int> bytes) async {
  final file = File(path);
  await file.writeAsBytes(bytes);
}
// coverage:ignore-end

/// Constructs an [ExportActions] bound to the live [ExportNotifier] +
/// [StorageRepository]. Override in tests.
final exportActionsProvider = Provider<ExportActions>((ref) {
  final notifier = ref.read(exportProvider.notifier);
  final storage = ref.read(storageRepositoryProvider);
  return ExportActions(notifier, storage);
});
