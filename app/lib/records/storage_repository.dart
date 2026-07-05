import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:wheelathlete/export/csv_exporter.dart';
import 'package:wheelathlete/export/csv_parser.dart';
import 'package:wheelathlete/records/session_model.dart';

/// One topic/subject folder in the storage hierarchy (Â§5 of architecture.md).
class TopicEntry {
  const TopicEntry({required this.name, this.description, this.createdAt});
  final String name;
  final String? description;
  final DateTime? createdAt;
}

/// Abstract storage for the WheelAthlete folder hierarchy:
/// ```
/// WheelAthleteData/
/// â””â”€â”€ <topic>/
///     â”œâ”€â”€ topic_meta.json
///     â””â”€â”€ trial_<NN>/
///         â”œâ”€â”€ session_<id>.csv
///         â””â”€â”€ session_<id>_meta.json
/// ```
///
/// The app talks to this interface; the real implementation
/// ([PathProviderStorageRepository]) wraps `path_provider` + `dart:io`, and
/// tests inject [InMemoryStorageRepository].
abstract class StorageRepository {
  /// Lists all topic folders, sorted by name.
  Future<List<TopicEntry>> listTopics();

  /// Creates a new topic folder + `topic_meta.json`. Throws if it exists.
  Future<void> createTopic(String name, {String? description});

  /// Renames a topic folder from [oldName] to [newName] (moves the directory).
  /// Throws if [oldName] doesn't exist or [newName] already exists. No-op if
  /// the names are identical.
  Future<void> renameTopic(String oldName, String newName);

  /// Updates the description stored in `topic_meta.json` for [name]. Pass
  /// `null` to clear it. Throws if the topic doesn't exist.
  Future<void> updateTopicDescription(String name, String? description);

  /// Deletes a topic folder and all its trials/sessions.
  Future<void> deleteTopic(String name);

  /// Deletes a trial folder and all sessions inside it. Throws if the trial
  /// does not exist.
  Future<void> deleteTrial(String topic, int trialNumber);

  /// Returns the next trial number for [topic] (max existing + 1, or 1).
  Future<int> nextTrialNumber(String topic);

  /// Saves a session: writes `session_<id>.csv` + `session_<id>_meta.json`
  /// under `<topic>/trial_<NN>/`. Creates the trial folder if needed.
  Future<void> saveSession(
    String topic,
    SessionMeta meta,
    List<BufferedSample> samples,
  );

  /// Reads the session metadata, or null if not found.
  Future<SessionMeta?> readSessionMeta(
    String topic,
    int trialNumber,
    String sessionId,
  );

  /// Lists all session metas for a given topic/trial.
  Future<List<SessionMeta>> listSessions(String topic, int trialNumber);

  /// Deletes a single session (meta + CSV).
  Future<void> deleteSession(
    String topic,
    int trialNumber,
    String sessionId,
  );

  /// Updates the editable fields of a session's metadata (notes + video
  /// filename). Other fields are preserved. Throws if the session doesn't
  /// exist.
  Future<void> updateSessionMeta(
    String topic,
    int trialNumber,
    String sessionId, {
    String? notes,
    String? videoFile,
  });

  /// Updates the tags on a session's metadata. Replaces the existing tag list
  /// entirely. Other fields are preserved. Throws if the session doesn't exist.
  Future<void> updateSessionTags(
    String topic,
    int trialNumber,
    String sessionId,
    List<String> tags,
  );

  /// Returns a flat list of all session metas across every topic and trial.
  /// Used by the Browse search/filter and the Experiment tracker dashboard.
  Future<List<SessionMeta>> listAllSessions();

  /// Reads the samples for a session, or empty list if not found.
  Future<List<BufferedSample>> readSamples(
    String topic,
    int trialNumber,
    String sessionId,
  );

  /// Reads a chunk of samples `[offset, offset+count)` from the session CSV.
  /// Used by the preview page for lazy loading. Returns an empty list if
  /// [offset] is beyond the sample count or the session doesn't exist.
  ///
  /// Throws [ArgumentError] if [offset] is negative or [count] is <= 0.
  Future<List<BufferedSample>> readSampleChunk(
    String topic,
    int trialNumber,
    String sessionId, {
    required int offset,
    required int count,
  });

  /// Lists all trial numbers for a topic, sorted ascending.
  Future<List<int>> listTrials(String topic);

  /// Returns the absolute file path for a session's CSV file.
  /// Used by share_plus to share the file.
  Future<String> getSessionCsvPath(
    String topic,
    int trialNumber,
    String sessionId,
  );

  /// Returns the absolute directory path for a trial folder.
  /// Used by share_plus to share the entire trial.
  Future<String> getTrialDirPath(String topic, int trialNumber);

  /// Returns the absolute directory path for a topic folder.
  /// Used by share_plus to share the entire topic.
  Future<String> getTopicDirPath(String topic);

  /// Writes CSV content to the session's CSV file. For in-memory storage,
  /// this is a no-op (samples are already stored). For file-based storage,
  /// this writes the CSV to disk.
  Future<void> writeSessionCsv(
    String topic,
    int trialNumber,
    String sessionId,
    String csvContent,
  );
}

// â”€â”€ path_provider implementation â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// coverage:ignore-start
// This production adapter wraps path_provider + dart:io which requires a real
// device filesystem. It is a thin I/O translator. The pure logic (folder
// hierarchy, meta JSON) is tested via InMemoryStorageRepository.

class PathProviderStorageRepository implements StorageRepository {
  /// Optional [rootDir] for tests. When null, the real
  /// `getApplicationDocumentsDirectory()` is used at runtime.
  PathProviderStorageRepository({this.rootDir});

  /// When non-null, overrides the on-disk root directory. Tests pass a temp
  /// directory here so the full CSV writeâ†’fileâ†’read round-trip is exercised
  /// against a real filesystem without mocking `path_provider`.
  final Directory? rootDir;

  Future<Directory> _rootDir() async {
    if (rootDir != null) {
      if (!rootDir!.existsSync()) rootDir!.createSync(recursive: true);
      return rootDir!;
    }
    final docs = await getApplicationDocumentsDirectory();
    final root = Directory('${docs.path}/WheelAthleteData');
    if (!root.existsSync()) root.createSync(recursive: true);
    return root;
  }

  Directory _topicDir(Directory root, String topic) =>
      Directory('${root.path}/$topic');

  Directory _trialDir(Directory root, String topic, int trialNumber) =>
      Directory('${root.path}/$topic/trial_${trialNumber.toString().padLeft(2, '0')}');

  @override
  Future<List<TopicEntry>> listTopics() async {
    final root = await _rootDir();
    final dirs = root
        .listSync()
        .whereType<Directory>()
        .map((d) => d.path.split(Platform.pathSeparator).last)
        .where((name) => !name.startsWith('.'))
        .toList()
      ..sort();
    return dirs.map((name) {
      final metaFile = File('${_topicDir(root, name).path}/topic_meta.json');
      String? desc;
      DateTime? createdAt;
      if (metaFile.existsSync()) {
        final json = jsonDecode(metaFile.readAsStringSync()) as Map<String, dynamic>;
        desc = json['description'] as String?;
        final created = json['created_at'] as String?;
        if (created != null) createdAt = DateTime.parse(created);
      }
      return TopicEntry(name: name, description: desc, createdAt: createdAt);
    }).toList();
  }

  @override
  Future<void> createTopic(String name, {String? description}) async {
    final root = await _rootDir();
    final dir = _topicDir(root, name);
    if (dir.existsSync()) {
      throw StateError('Topic "$name" already exists');
    }
    dir.createSync(recursive: true);
    final metaFile = File('${dir.path}/topic_meta.json');
    metaFile.writeAsStringSync(jsonEncode({
      'description': description,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    }));
  }

  @override
  Future<void> deleteTopic(String name) async {
    final root = await _rootDir();
    final dir = _topicDir(root, name);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }

  @override
  Future<void> deleteTrial(String topic, int trialNumber) async {
    final root = await _rootDir();
    final trialDir = _trialDir(root, topic, trialNumber);
    if (!trialDir.existsSync()) {
      throw StateError(
        'Trial $trialNumber not found in topic "$topic"',
      );
    }
    trialDir.deleteSync(recursive: true);
  }

  @override
  Future<void> renameTopic(String oldName, String newName) async {
    if (oldName == newName) return;
    final root = await _rootDir();
    final oldDir = _topicDir(root, oldName);
    if (!oldDir.existsSync()) {
      throw StateError('Topic "$oldName" does not exist');
    }
    final newDir = _topicDir(root, newName);
    if (newDir.existsSync()) {
      throw StateError('Topic "$newName" already exists');
    }
    oldDir.renameSync(newDir.path);
  }

  @override
  Future<void> updateTopicDescription(String name, String? description) async {
    final root = await _rootDir();
    final dir = _topicDir(root, name);
    if (!dir.existsSync()) {
      throw StateError('Topic "$name" does not exist');
    }
    final metaFile = File('${dir.path}/topic_meta.json');
    Map<String, dynamic> json;
    if (metaFile.existsSync()) {
      json = jsonDecode(metaFile.readAsStringSync()) as Map<String, dynamic>;
    } else {
      json = <String, dynamic>{};
    }
    json['description'] = description;
    if (json['created_at'] == null) {
      json['created_at'] = DateTime.now().toUtc().toIso8601String();
    }
    metaFile.writeAsStringSync(jsonEncode(json));
  }

  @override
  Future<int> nextTrialNumber(String topic) async {
    final root = await _rootDir();
    final topicDir = _topicDir(root, topic);
    if (!topicDir.existsSync()) return 1;
    var maxTrial = 0;
    for (final entity in topicDir.listSync()) {
      if (entity is Directory) {
        final name = entity.path.split(Platform.pathSeparator).last;
        if (name.startsWith('trial_')) {
          final n = int.tryParse(name.substring(6));
          if (n != null && n > maxTrial) maxTrial = n;
        }
      }
    }
    // Also check meta files for higher trial numbers (in case folders were
    // deleted but sessions were saved with higher trial numbers).
    return maxTrial + 1;
  }

  @override
  Future<void> saveSession(
    String topic,
    SessionMeta meta,
    List<BufferedSample> samples,
  ) async {
    final root = await _rootDir();
    final trialDir = _trialDir(root, topic, meta.trialNumber);
    if (!trialDir.existsSync()) trialDir.createSync(recursive: true);
    // Write meta JSON.
    final metaFile = File('${trialDir.path}/session_${meta.sessionId}_meta.json');
    metaFile.writeAsStringSync(jsonEncode(meta.toJson()));
    // Write the actual CSV with all samples so readSamples/export works.
    final csvFile = File('${trialDir.path}/session_${meta.sessionId}.csv');
    final buf = StringBuffer();
    CsvExporter.writeToSink(buf, samples);
    csvFile.writeAsStringSync(buf.toString());
  }

  @override
  Future<SessionMeta?> readSessionMeta(
    String topic,
    int trialNumber,
    String sessionId,
  ) async {
    final root = await _rootDir();
    final trialDir = _trialDir(root, topic, trialNumber);
    final metaFile = File('${trialDir.path}/session_${sessionId}_meta.json');
    if (!metaFile.existsSync()) return null;
    final json = jsonDecode(metaFile.readAsStringSync()) as Map<String, dynamic>;
    return SessionMeta.fromJson(json);
  }

  @override
  Future<List<SessionMeta>> listSessions(String topic, int trialNumber) async {
    final root = await _rootDir();
    final trialDir = _trialDir(root, topic, trialNumber);
    if (!trialDir.existsSync()) return [];
    final metas = <SessionMeta>[];
    for (final entity in trialDir.listSync()) {
      if (entity is File && entity.path.endsWith('_meta.json')) {
        final json = jsonDecode(entity.readAsStringSync()) as Map<String, dynamic>;
        metas.add(SessionMeta.fromJson(json));
      }
    }
    return metas;
  }

  @override
  Future<void> deleteSession(
    String topic,
    int trialNumber,
    String sessionId,
  ) async {
    final root = await _rootDir();
    final trialDir = _trialDir(root, topic, trialNumber);
    final metaFile = File('${trialDir.path}/session_${sessionId}_meta.json');
    final csvFile = File('${trialDir.path}/session_$sessionId.csv');
    if (metaFile.existsSync()) metaFile.deleteSync();
    if (csvFile.existsSync()) csvFile.deleteSync();
  }

  @override
  Future<void> updateSessionMeta(
    String topic,
    int trialNumber,
    String sessionId, {
    String? notes,
    String? videoFile,
  }) async {
    final root = await _rootDir();
    final trialDir = _trialDir(root, topic, trialNumber);
    final metaFile = File('${trialDir.path}/session_${sessionId}_meta.json');
    if (!metaFile.existsSync()) {
      throw StateError(
        'Session not found: $topic/trial_$trialNumber/$sessionId',
      );
    }
    final json =
        jsonDecode(metaFile.readAsStringSync()) as Map<String, dynamic>;
    json['notes'] = notes;
    json['video_file_name'] = videoFile;
    metaFile.writeAsStringSync(jsonEncode(json));
  }

  @override
  Future<void> updateSessionTags(
    String topic,
    int trialNumber,
    String sessionId,
    List<String> tags,
  ) async {
    final root = await _rootDir();
    final trialDir = _trialDir(root, topic, trialNumber);
    final metaFile = File('${trialDir.path}/session_${sessionId}_meta.json');
    if (!metaFile.existsSync()) {
      throw StateError(
        'Session not found: $topic/trial_$trialNumber/$sessionId',
      );
    }
    final json =
        jsonDecode(metaFile.readAsStringSync()) as Map<String, dynamic>;
    json['tags'] = tags;
    metaFile.writeAsStringSync(jsonEncode(json));
  }

  @override
  Future<List<SessionMeta>> listAllSessions() async {
    final root = await _rootDir();
    final all = <SessionMeta>[];
    for (final entity in root.listSync()) {
      if (entity is! Directory) continue;
      final topicName = entity.path.split(Platform.pathSeparator).last;
      if (topicName.startsWith('.')) continue;
      for (final trialEntity in entity.listSync()) {
        if (trialEntity is! Directory) continue;
        for (final file in trialEntity.listSync()) {
          if (file is File && file.path.endsWith('_meta.json')) {
            final json =
                jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
            all.add(SessionMeta.fromJson(json));
          }
        }
      }
    }
    return all;
  }

  @override
  Future<List<BufferedSample>> readSamples(
    String topic,
    int trialNumber,
    String sessionId,
  ) async {
    final root = await _rootDir();
    final trialDir = _trialDir(root, topic, trialNumber);
    final csvFile = File('${trialDir.path}/session_$sessionId.csv');
    if (!csvFile.existsSync()) return [];
    // Route through the shared [CsvSampleParser] so the exact same parsing
    // logic exercised by the test suite runs on real on-device files. The
    // parser merges the L and R tables back into one chronological list and
    // tolerates malformed rows without throwing.
    return CsvSampleParser.parse(csvFile.readAsStringSync());
  }

  @override
  Future<List<BufferedSample>> readSampleChunk(
    String topic,
    int trialNumber,
    String sessionId, {
    required int offset,
    required int count,
  }) async {
    if (offset < 0) {
      throw ArgumentError.value(offset, 'offset', 'must be >= 0');
    }
    if (count <= 0) {
      throw ArgumentError.value(count, 'count', 'must be > 0');
    }
    final root = await _rootDir();
    final trialDir = _trialDir(root, topic, trialNumber);
    final csvFile = File('${trialDir.path}/session_$sessionId.csv');
    if (!csvFile.existsSync()) return [];
    // Route through the shared [CsvSampleParser] so chunk offsets have the
    // same semantics as [readSamples]: index N = the Nth sample in the
    // chronological, both-wheels-merged timeline. The on-disk format stores
    // L and R as two separate blocks, so a naive "Nth data line in file
    // order" would return L samples for low offsets and R samples for high
    // ones â€” wrong for the preview scrubber, which maps a scrub position
    // (ms from start) to a flat sample index via `sampleRateHz`.
    //
    // Sessions are bounded (~10 min Ã— 100 Hz Ã— 2 wheels â‰ˆ 120k samples,
    // ~5 MB CSV), so buffering the whole file to merge is acceptable and
    // keeps the read path identical to [readSamples].
    final all = CsvSampleParser.parse(csvFile.readAsStringSync());
    if (offset >= all.length) return [];
    return all.skip(offset).take(count).toList();
  }

  @override
  Future<List<int>> listTrials(String topic) async {
    final root = await _rootDir();
    final topicDir = Directory('${root.path}/$topic');
    if (!topicDir.existsSync()) return [];
    final trials = <int>[];
    for (final entity in topicDir.listSync()) {
      if (entity is Directory) {
        final name = entity.path.split(Platform.pathSeparator).last;
        if (name.startsWith('trial_')) {
          final n = int.tryParse(name.substring(6));
          if (n != null) trials.add(n);
        }
      }
    }
    trials.sort();
    return trials;
  }

  @override
  Future<String> getSessionCsvPath(
    String topic,
    int trialNumber,
    String sessionId,
  ) async {
    final root = await _rootDir();
    final trialDir = _trialDir(root, topic, trialNumber);
    return '${trialDir.path}/session_$sessionId.csv';
  }

  @override
  Future<String> getTrialDirPath(String topic, int trialNumber) async {
    final root = await _rootDir();
    return _trialDir(root, topic, trialNumber).path;
  }

  @override
  Future<String> getTopicDirPath(String topic) async {
    final root = await _rootDir();
    return '${root.path}/$topic';
  }

  @override
  Future<void> writeSessionCsv(
    String topic,
    int trialNumber,
    String sessionId,
    String csvContent,
  ) async {
    final root = await _rootDir();
    final trialDir = _trialDir(root, topic, trialNumber);
    if (!trialDir.existsSync()) trialDir.createSync(recursive: true);
    final csvFile = File('${trialDir.path}/session_$sessionId.csv');
    await csvFile.writeAsString(csvContent);
  }
}
// coverage:ignore-end

// â”€â”€ In-memory fake for tests â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class InMemoryStorageRepository implements StorageRepository {
  final _topics = <String, TopicEntry>{};
  final _sessions = <String, List<SessionMeta>>{}; // key: "topic/trialNN"
  final _samples = <String, List<BufferedSample>>{}; // key: "topic/trialNN/sessionId"

  @override
  Future<List<TopicEntry>> listTopics() async {
    final names = _topics.keys.toList()..sort();
    return names.map((n) => _topics[n]!).toList();
  }

  @override
  Future<void> createTopic(String name, {String? description}) async {
    if (_topics.containsKey(name)) {
      throw StateError('Topic "$name" already exists');
    }
    _topics[name] = TopicEntry(
      name: name,
      description: description,
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<void> deleteTopic(String name) async {
    _topics.remove(name);
    _sessions.removeWhere((key, _) => key.startsWith('$name/'));
    _samples.removeWhere((key, _) => key.startsWith('$name/'));
  }

  @override
  Future<void> deleteTrial(String topic, int trialNumber) async {
    final key = '$topic/trial${trialNumber.toString().padLeft(2, '0')}';
    if (!_sessions.containsKey(key)) {
      throw StateError(
        'Trial $trialNumber not found in topic "$topic"',
      );
    }
    _sessions.remove(key);
    _samples.removeWhere((k, _) => k.startsWith('$key/'));
  }

  @override
  Future<void> renameTopic(String oldName, String newName) async {
    if (oldName == newName) return;
    final entry = _topics.remove(oldName);
    if (entry == null) {
      throw StateError('Topic "$oldName" does not exist');
    }
    if (_topics.containsKey(newName)) {
      // Put it back so the operation is rolled back.
      _topics[oldName] = entry;
      throw StateError('Topic "$newName" already exists');
    }
    _topics[newName] = TopicEntry(
      name: newName,
      description: entry.description,
      createdAt: entry.createdAt,
    );
    // Move sessions + samples keyed by "oldName/...".
    final sessionKeys = _sessions.keys
        .where((k) => k.startsWith('$oldName/'))
        .toList();
    for (final k in sessionKeys) {
      final v = _sessions.remove(k)!;
      _sessions[k.replaceFirst('$oldName/', '$newName/')] = v;
    }
    final sampleKeys = _samples.keys
        .where((k) => k.startsWith('$oldName/'))
        .toList();
    for (final k in sampleKeys) {
      final v = _samples.remove(k)!;
      _samples[k.replaceFirst('$oldName/', '$newName/')] = v;
    }
  }

  @override
  Future<void> updateTopicDescription(String name, String? description) async {
    final entry = _topics[name];
    if (entry == null) {
      throw StateError('Topic "$name" does not exist');
    }
    _topics[name] = TopicEntry(
      name: name,
      description: description,
      createdAt: entry.createdAt,
    );
  }

  @override
  Future<void> updateSessionMeta(
    String topic,
    int trialNumber,
    String sessionId, {
    String? notes,
    String? videoFile,
  }) async {
    final key = '$topic/trial${trialNumber.toString().padLeft(2, '0')}';
    final metas = _sessions[key];
    if (metas == null) {
      throw StateError(
        'Session not found: $topic/trial_$trialNumber/$sessionId',
      );
    }
    final i = metas.indexWhere((m) => m.sessionId == sessionId);
    if (i < 0) {
      throw StateError(
        'Session not found: $topic/trial_$trialNumber/$sessionId',
      );
    }
    final old = metas[i];
    metas[i] = SessionMeta(
      sessionId: old.sessionId,
      topic: old.topic,
      trialNumber: old.trialNumber,
      athleteName: old.athleteName,
      sampleRateHz: old.sampleRateHz,
      startTime: old.startTime,
      durationMs: old.durationMs,
      sampleCount: old.sampleCount,
      markerCount: old.markerCount,
      offsetUsLeft: old.offsetUsLeft,
      offsetUsRight: old.offsetUsRight,
      driftResidualRmsMsLeft: old.driftResidualRmsMsLeft,
      driftResidualRmsMsRight: old.driftResidualRmsMsRight,
      notes: notes,
      videoFileName: videoFile,
      utcStartMs: old.utcStartMs,
      tags: old.tags,
      protocolTemplateId: old.protocolTemplateId,
    );
  }

  @override
  Future<void> updateSessionTags(
    String topic,
    int trialNumber,
    String sessionId,
    List<String> tags,
  ) async {
    final key = '$topic/trial${trialNumber.toString().padLeft(2, '0')}';
    final metas = _sessions[key];
    if (metas == null) {
      throw StateError(
        'Session not found: $topic/trial_$trialNumber/$sessionId',
      );
    }
    final i = metas.indexWhere((m) => m.sessionId == sessionId);
    if (i < 0) {
      throw StateError(
        'Session not found: $topic/trial_$trialNumber/$sessionId',
      );
    }
    final old = metas[i];
    metas[i] = SessionMeta(
      sessionId: old.sessionId,
      topic: old.topic,
      trialNumber: old.trialNumber,
      athleteName: old.athleteName,
      sampleRateHz: old.sampleRateHz,
      startTime: old.startTime,
      durationMs: old.durationMs,
      sampleCount: old.sampleCount,
      markerCount: old.markerCount,
      offsetUsLeft: old.offsetUsLeft,
      offsetUsRight: old.offsetUsRight,
      driftResidualRmsMsLeft: old.driftResidualRmsMsLeft,
      driftResidualRmsMsRight: old.driftResidualRmsMsRight,
      notes: old.notes,
      videoFileName: old.videoFileName,
      utcStartMs: old.utcStartMs,
      tags: List<String>.from(tags),
      protocolTemplateId: old.protocolTemplateId,
    );
  }

  @override
  Future<List<SessionMeta>> listAllSessions() async {
    final all = <SessionMeta>[];
    for (final metas in _sessions.values) {
      all.addAll(metas);
    }
    return all;
  }

  @override
  Future<int> nextTrialNumber(String topic) async {
    var maxTrial = 0;
    for (final entry in _sessions.entries) {
      if (entry.key.startsWith('$topic/')) {
        for (final meta in entry.value) {
          if (meta.trialNumber > maxTrial) maxTrial = meta.trialNumber;
        }
      }
    }
    return maxTrial + 1;
  }

  @override
  Future<void> saveSession(
    String topic,
    SessionMeta meta,
    List<BufferedSample> samples,
  ) async {
    final key = '$topic/trial${meta.trialNumber.toString().padLeft(2, '0')}';
    _sessions.putIfAbsent(key, () => []).add(meta);
    _samples['$key/${meta.sessionId}'] = samples;
  }

  @override
  Future<SessionMeta?> readSessionMeta(
    String topic,
    int trialNumber,
    String sessionId,
  ) async {
    final key = '$topic/trial${trialNumber.toString().padLeft(2, '0')}';
    final metas = _sessions[key];
    if (metas == null) return null;
    for (final m in metas) {
      if (m.sessionId == sessionId) return m;
    }
    return null;
  }

  @override
  Future<List<SessionMeta>> listSessions(String topic, int trialNumber) async {
    final key = '$topic/trial${trialNumber.toString().padLeft(2, '0')}';
    return List<SessionMeta>.from(_sessions[key] ?? []);
  }

  @override
  Future<void> deleteSession(
    String topic,
    int trialNumber,
    String sessionId,
  ) async {
    final key = '$topic/trial${trialNumber.toString().padLeft(2, '0')}';
    _sessions[key]?.removeWhere((m) => m.sessionId == sessionId);
    _samples.remove('$key/$sessionId');
  }

  @override
  Future<List<BufferedSample>> readSamples(
    String topic,
    int trialNumber,
    String sessionId,
  ) async {
    final key = '$topic/trial${trialNumber.toString().padLeft(2, '0')}';
    return List<BufferedSample>.from(_samples['$key/$sessionId'] ?? []);
  }

  @override
  Future<List<BufferedSample>> readSampleChunk(
    String topic,
    int trialNumber,
    String sessionId, {
    required int offset,
    required int count,
  }) async {
    if (offset < 0) {
      throw ArgumentError.value(offset, 'offset', 'must be >= 0');
    }
    if (count <= 0) {
      throw ArgumentError.value(count, 'count', 'must be > 0');
    }
    final key = '$topic/trial${trialNumber.toString().padLeft(2, '0')}';
    final all = _samples['$key/$sessionId'];
    if (all == null || offset >= all.length) return [];
    final end = (offset + count < all.length) ? offset + count : all.length;
    return all.sublist(offset, end);
  }

  @override
  Future<List<int>> listTrials(String topic) async {
    final trials = <int>{};
    for (final key in _sessions.keys) {
      if (key.startsWith('$topic/')) {
        final trialPart = key.substring(topic.length + 1); // 'trialNN'
        if (trialPart.startsWith('trial')) {
          final n = int.tryParse(trialPart.substring(5));
          if (n != null) trials.add(n);
        }
      }
    }
    final sorted = trials.toList()..sort();
    return sorted;
  }

  @override
  Future<String> getSessionCsvPath(
    String topic,
    int trialNumber,
    String sessionId,
  ) async {
    // In-memory fake returns a synthetic path; tests should use readSamples
    // instead of file paths.
    return 'memory://$topic/trial_${trialNumber.toString().padLeft(2, '0')}/session_$sessionId.csv';
  }

  @override
  Future<String> getTrialDirPath(String topic, int trialNumber) async {
    return 'memory://$topic/trial_${trialNumber.toString().padLeft(2, '0')}';
  }

  @override
  Future<String> getTopicDirPath(String topic) async {
    return 'memory://$topic';
  }

  @override
  Future<void> writeSessionCsv(
    String topic,
    int trialNumber,
    String sessionId,
    String csvContent,
  ) async {
    // In-memory storage doesn't write files. The CSV content is generated
    // on-demand from the stored samples.
  }
}
