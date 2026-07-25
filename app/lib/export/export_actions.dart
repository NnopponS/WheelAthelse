import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:wheelathlete/export/csv_exporter.dart';
import 'package:wheelathlete/records/session_model.dart';
import 'package:wheelathlete/records/storage_repository.dart';
import 'package:wheelathlete/theme/theme.dart';

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

/// Writes [bytes] to the file at [path]. Abstracted so tests can fake it.
typedef FileSink = Future<void> Function(String path, List<int> bytes);
typedef DirectoryCreator = Future<void> Function(String path);
typedef DirectoryRenamer = Future<void> Function(String from, String to);
typedef DirectoryRemover = Future<void> Function(String path);

sealed class TopicExportResult {
  const TopicExportResult();
}

final class TopicExportSuccess extends TopicExportResult {
  const TopicExportSuccess(this.directory, this.files);
  final String directory;
  final List<String> files;
}

final class TopicExportCancelled extends TopicExportResult {
  const TopicExportCancelled();
}

final class TopicExportFailure extends TopicExportResult {
  const TopicExportFailure(this.error);
  final Object error;
}

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

    Future<void> writeTrial(int trial) async {
      final metas = await _storage.listSessions(topic, trial);
      if (metas.isEmpty) return;
      final samples = <BufferedSample>[];
      for (final meta in metas) {
        samples.addAll(
          await _storage.readSamples(topic, trial, meta.sessionId),
        );
      }
      if (samples.isEmpty) return;
      metas.sort((a, b) => a.startTime.compareTo(b.startTime));
      final date = metas.first.startTime.toLocal().toIso8601String().substring(
        0,
        10,
      );
      final safeTopic = _safeFilePart(topic);
      final stem =
          '${safeTopic}_trial_${trial.toString().padLeft(2, '0')}_$date';
      final outputs = <String, String>{
        '${stem}_left_raw.csv': CsvExporter.toRawCsvString(
          samples,
          WheelSide.left,
        ),
        '${stem}_right_raw.csv': CsvExporter.toRawCsvString(
          samples,
          WheelSide.right,
        ),
        '${stem}_training.csv': CsvExporter.toAlignedTrainingCsvString(
          samples,
          gridIntervalUs: 1000000 ~/ metas.first.sampleRateHz,
        ),
        '$stem.metadata.json': jsonEncode({
          'export_schema': 2,
          'sessions': metas.map((meta) => meta.toJson()).toList(),
        }),
      };
      for (final output in outputs.entries) {
        final path = _availablePath('$dir/${output.key}');
        await writeFile(path, utf8.encode(output.value));
        written.add(path);
      }
    }

    switch (level) {
      case ExportLevel.session:
        await writeTrial(trialNumber!);
      case ExportLevel.trial:
        await writeTrial(trialNumber!);
      case ExportLevel.topic:
        final trials = await _storage.listTrials(topic);
        for (final t in trials) {
          await writeTrial(t);
        }
    }
    return written;
  }

  /// Atomically exports every trial in one selected topic into a real folder.
  Future<TopicExportResult> exportTopicFolder({
    required String topic,
    required DirectoryPicker pickDirectory,
    required FileSink writeFile,
    DirectoryCreator? createDirectory,
    DirectoryRenamer? renameDirectory,
    DirectoryRemover? removeDirectory,
  }) async {
    final parent = await pickDirectory();
    if (parent == null) return const TopicExportCancelled();
    final create =
        createDirectory ??
        (path) async => Directory(path).create(recursive: true);
    final rename =
        renameDirectory ?? (from, to) async => Directory(from).rename(to);
    final remove =
        removeDirectory ??
        (path) async {
          final dir = Directory(path);
          if (dir.existsSync()) await dir.delete(recursive: true);
        };
    final safeTopic = _safeFilePart(topic).isEmpty
        ? 'topic'
        : _safeFilePart(topic);
    final destination = _availableDirectory('$parent/$safeTopic');
    final temporary =
        '$destination.tmp_${DateTime.now().microsecondsSinceEpoch}';
    final files = <String>[];
    try {
      await create(temporary);
      final trials = await _storage.listTrials(topic);
      for (final trial in trials) {
        final metas = await _storage.listSessions(topic, trial);
        if (metas.isEmpty) continue;
        metas.sort((a, b) => a.startTime.compareTo(b.startTime));
        final samples = <BufferedSample>[];
        for (final meta in metas) {
          samples.addAll(
            await _storage.readSamples(topic, trial, meta.sessionId),
          );
        }
        final date = metas.first.startTime
            .toLocal()
            .toIso8601String()
            .substring(0, 10);
        final stem =
            '${safeTopic}_trial_${trial.toString().padLeft(2, '0')}_$date';
        final leftPath = '$temporary/${stem}_left_raw.csv';
        final rightPath = '$temporary/${stem}_right_raw.csv';
        final trainingPath = '$temporary/${stem}_training.csv';
        final metadataPath = '$temporary/$stem.metadata.json';
        await writeFile(
          leftPath,
          utf8.encode(CsvExporter.toRawCsvString(samples, WheelSide.left)),
        );
        await writeFile(
          rightPath,
          utf8.encode(CsvExporter.toRawCsvString(samples, WheelSide.right)),
        );
        await writeFile(
          trainingPath,
          utf8.encode(
            CsvExporter.toAlignedTrainingCsvString(
              samples,
              gridIntervalUs: 1000000 ~/ metas.first.sampleRateHz,
            ),
          ),
        );
        await writeFile(
          metadataPath,
          utf8.encode(
            jsonEncode({
              'export_schema': 2,
              'sessions': metas.map((meta) => meta.toJson()).toList(),
            }),
          ),
        );
        files.addAll([
          '$destination/${stem}_left_raw.csv',
          '$destination/${stem}_right_raw.csv',
          '$destination/${stem}_training.csv',
          '$destination/$stem.metadata.json',
        ]);
      }
      final manifestPath = '$temporary/manifest.json';
      await writeFile(
        manifestPath,
        utf8.encode(
          jsonEncode({
            'product': 'WheelAthlete',
            'topic': topic,
            'app_version': '1.7.0+8',
            'firmware_version': '1.7.0',
            'protocol_version': '1.7.0',
            'session_schema_version': 4,
            'export_schema_version': 2,
            'trial_count': trials.length,
            'exported_at': DateTime.now().toUtc().toIso8601String(),
          }),
        ),
      );
      files.add('$destination/manifest.json');
      await rename(temporary, destination);
      return TopicExportSuccess(destination, List.unmodifiable(files));
    } on Object catch (error) {
      await remove(temporary);
      return TopicExportFailure(error);
    }
  }

  /// Exports the complete repository as a portable ZIP with one combined CSV
  /// and metadata JSON per trial plus a versioned manifest.
  Future<String?> exportAllZip({
    required DirectoryPicker pickDirectory,
    required FileSink writeFile,
  }) async {
    final dir = await pickDirectory();
    if (dir == null) return null;
    final archive = Archive();
    final topics = await _storage.listTopics();
    var trialCount = 0;
    for (final topic in topics) {
      final trials = await _storage.listTrials(topic.name);
      for (final trial in trials) {
        final metas = await _storage.listSessions(topic.name, trial);
        if (metas.isEmpty) continue;
        final samples = <BufferedSample>[];
        for (final meta in metas) {
          samples.addAll(
            await _storage.readSamples(topic.name, trial, meta.sessionId),
          );
        }
        metas.sort((a, b) => a.startTime.compareTo(b.startTime));
        final safeTopic = _safeFilePart(topic.name);
        final base = '$safeTopic/trial_${trial.toString().padLeft(2, '0')}';
        final left = utf8.encode(
          CsvExporter.toRawCsvString(samples, WheelSide.left),
        );
        final right = utf8.encode(
          CsvExporter.toRawCsvString(samples, WheelSide.right),
        );
        final training = utf8.encode(
          CsvExporter.toAlignedTrainingCsvString(
            samples,
            gridIntervalUs: 1000000 ~/ metas.first.sampleRateHz,
          ),
        );
        archive.addFile(ArchiveFile('$base/left_raw.csv', left.length, left));
        archive.addFile(
          ArchiveFile('$base/right_raw.csv', right.length, right),
        );
        archive.addFile(
          ArchiveFile('$base/training.csv', training.length, training),
        );
        final metadata = utf8.encode(
          jsonEncode(metas.map((m) => m.toJson()).toList()),
        );
        archive.addFile(
          ArchiveFile('$base/metadata.json', metadata.length, metadata),
        );
        trialCount++;
      }
    }
    final manifest = utf8.encode(
      jsonEncode({
        'product': 'WheelAthlete',
        'app_version': '1.7.0+8',
        'firmware_version': '1.7.0',
        'protocol_version': '1.7.0',
        'session_schema_version': 4,
        'export_schema_version': 2,
        'topic_count': topics.length,
        'trial_count': trialCount,
        'exported_at': DateTime.now().toUtc().toIso8601String(),
      }),
    );
    archive.addFile(ArchiveFile('manifest.json', manifest.length, manifest));
    final bytes = ZipEncoder().encode(archive)!;
    final path = _availablePath(
      '$dir/WheelAthlete_all_data_${DateTime.now().toIso8601String().substring(0, 10)}.zip',
    );
    await writeFile(path, bytes);
    return path;
  }

  static String _safeFilePart(String value) {
    final cleaned = value.trim().replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    return cleaned
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  static String _availablePath(String requested) {
    if (!File(requested).existsSync()) return requested;
    final dot = requested.lastIndexOf('.');
    final stem = dot < 0 ? requested : requested.substring(0, dot);
    final extension = dot < 0 ? '' : requested.substring(dot);
    var suffix = 2;
    while (File('${stem}_$suffix$extension').existsSync()) {
      suffix++;
    }
    return '${stem}_$suffix$extension';
  }

  static String _availableDirectory(String requested) {
    if (!Directory(requested).existsSync()) return requested;
    var suffix = 2;
    while (Directory('${requested}_$suffix').existsSync()) {
      suffix++;
    }
    return '${requested}_$suffix';
  }
}
