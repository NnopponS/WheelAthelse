import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:wheelathlete/records/session_model.dart';

/// One topic/subject folder in the storage hierarchy (§5 of architecture.md).
class TopicEntry {
  const TopicEntry({required this.name, this.description, this.createdAt});
  final String name;
  final String? description;
  final DateTime? createdAt;
}

/// Abstract storage for the WheelAthlete folder hierarchy:
/// ```
/// WheelAthleteData/
/// └── <topic>/
///     ├── topic_meta.json
///     └── trial_<NN>/
///         ├── session_<id>.csv
///         └── session_<id>_meta.json
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

  /// Deletes a topic folder and all its trials/sessions.
  Future<void> deleteTopic(String name);

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
}

// ── path_provider implementation ──────────────────────────────────────────
// coverage:ignore-start
// This production adapter wraps path_provider + dart:io which requires a real
// device filesystem. It is a thin I/O translator. The pure logic (folder
// hierarchy, meta JSON) is tested via InMemoryStorageRepository.

class PathProviderStorageRepository implements StorageRepository {
  PathProviderStorageRepository();

  Future<Directory> _rootDir() async {
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
    // CSV is written by the exporter (subtask #9). Here we just write a
    // placeholder so the file exists.
    final csvFile = File('${trialDir.path}/session_${meta.sessionId}.csv');
    if (!csvFile.existsSync()) csvFile.writeAsStringSync('');
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
}
// coverage:ignore-end

// ── In-memory fake for tests ──────────────────────────────────────────────

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
}
