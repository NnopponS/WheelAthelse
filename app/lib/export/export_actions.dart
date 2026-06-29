import 'package:wheelathlete/export/csv_exporter.dart';
import 'package:wheelathlete/records/storage_repository.dart';

/// Which level of the folder hierarchy an export/share action targets.
enum ExportLevel { session, trial, topic }

/// Share operations that [ExportNotifier] implements. Abstracted so
/// [ExportActions] can be unit-tested with a fake instead of the real
/// share_plus-backed notifier.
abstract class ExportOperations {
  Future<void> shareSession({
    required String topic,
    required int trialNumber,
    required String sessionId,
  });

  Future<void> shareTrial({required String topic, required int trialNumber});

  Future<void> shareTopic({required String topic});
}

/// Function that pops the platform directory picker and returns the chosen
/// path, or null if the user cancelled. Abstracted so tests can fake it.
typedef DirectoryPicker = Future<String?> Function();

/// Writes [content] to the file at [path]. Abstracted so tests can fake it.
typedef FileSink = Future<void> Function(String path, String content);

/// Decides which export/share method to call for a given [ExportLevel] and
/// implements save-to-device: writes one CSV per session into a user-picked
/// directory.
///
/// The share dispatch is a thin switch over [ExportOperations]; save-to-device
/// reads samples from [StorageRepository], formats them via [CsvExporter], and
/// writes each session's CSV into the picked directory.
class ExportActions {
  ExportActions(this._ops, this._storage);

  final ExportOperations _ops;
  final StorageRepository _storage;

  /// Shares the session/trial/topic via share_plus (delegates to
  /// [ExportOperations]).
  Future<void> share({
    required ExportLevel level,
    required String topic,
    int? trialNumber,
    String? sessionId,
  }) {
    switch (level) {
      case ExportLevel.session:
        return _ops.shareSession(
          topic: topic,
          trialNumber: trialNumber!,
          sessionId: sessionId!,
        );
      case ExportLevel.trial:
        return _ops.shareTrial(topic: topic, trialNumber: trialNumber!);
      case ExportLevel.topic:
        return _ops.shareTopic(topic: topic);
    }
  }

  /// Saves the session/trial/topic CSV(s) to a user-picked directory. Returns
  /// the list of written file paths (empty if the user cancelled the picker).
  Future<List<String>> saveToDevice({
    required ExportLevel level,
    required String topic,
    int? trialNumber,
    String? sessionId,
    required DirectoryPicker pickDirectory,
    required FileSink writeFile,
  }) async {
    final dir = await pickDirectory();
    if (dir == null) return const [];
    final written = <String>[];

    Future<void> writeSession(String sid, int trial) async {
      final samples = await _storage.readSamples(topic, trial, sid);
      final csv = CsvExporter.toCsvString(samples);
      final path = '$dir/session_$sid.csv';
      await writeFile(path, csv);
      written.add(path);
    }

    switch (level) {
      case ExportLevel.session:
        await writeSession(sessionId!, trialNumber!);
      case ExportLevel.trial:
        final metas = await _storage.listSessions(topic, trialNumber!);
        for (final m in metas) {
          await writeSession(m.sessionId, trialNumber);
        }
      case ExportLevel.topic:
        final trials = await _storage.listTrials(topic);
        for (final t in trials) {
          final metas = await _storage.listSessions(topic, t);
          for (final m in metas) {
            await writeSession(m.sessionId, t);
          }
        }
    }
    return written;
  }
}
