import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:wheelathlete/records/protocol_template.dart';

/// Abstract storage for protocol templates (Phase 3, §1 of
/// architecture-phase3.md).
///
/// Templates are persisted as a single `protocols.json` file in the app
/// documents directory (alongside `WheelAthleteData/`). The app talks to this
/// interface; the real implementation ([PathProviderProtocolRepository]) wraps
/// `path_provider` + `dart:io`, and tests inject
/// [InMemoryProtocolRepository].
abstract class ProtocolRepository {
  /// Lists all templates, sorted by name.
  Future<List<ProtocolTemplate>> listTemplates();

  /// Returns the template with [id], or null if not found.
  Future<ProtocolTemplate?> getTemplate(String id);

  /// Creates a new template with a generated hex-timestamp id and returns it.
  Future<ProtocolTemplate> createTemplate({
    required String name,
    String? description,
    required String topicName,
    required int targetTrialCount,
    int sampleRateHz = 100,
  });

  /// Updates an existing template (matched by [template.id]). Throws if the
  /// template doesn't exist.
  Future<void> updateTemplate(ProtocolTemplate template);

  /// Deletes the template with [id]. No-op if not found.
  Future<void> deleteTemplate(String id);
}

// ── path_provider implementation ──────────────────────────────────────────
// coverage:ignore-start
// This production adapter wraps path_provider + dart:io which requires a real
// device filesystem. It is a thin I/O translator. The pure logic (CRUD on the
// template list) is tested via InMemoryProtocolRepository.

class PathProviderProtocolRepository implements ProtocolRepository {
  PathProviderProtocolRepository();

  Future<File> _file() async {
    final docs = await getApplicationDocumentsDirectory();
    return File('${docs.path}/protocols.json');
  }

  Future<List<ProtocolTemplate>> _read() async {
    final file = await _file();
    if (!file.existsSync()) return [];
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final list = json['templates'] as List? ?? const [];
    return list
        .map((e) => ProtocolTemplate.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> _write(List<ProtocolTemplate> templates) async {
    final file = await _file();
    file.writeAsStringSync(
      jsonEncode({'templates': templates.map((t) => t.toJson()).toList()}),
    );
  }

  @override
  Future<List<ProtocolTemplate>> listTemplates() async {
    final templates = await _read();
    templates.sort((a, b) => a.name.compareTo(b.name));
    return templates;
  }

  @override
  Future<ProtocolTemplate?> getTemplate(String id) async {
    final templates = await _read();
    for (final t in templates) {
      if (t.id == id) return t;
    }
    return null;
  }

  @override
  Future<ProtocolTemplate> createTemplate({
    required String name,
    String? description,
    required String topicName,
    required int targetTrialCount,
    int sampleRateHz = 100,
  }) async {
    final now = DateTime.now();
    final template = ProtocolTemplate(
      id: now.millisecondsSinceEpoch.toRadixString(16),
      name: name,
      description: description,
      topicName: topicName,
      targetTrialCount: targetTrialCount,
      sampleRateHz: sampleRateHz,
      createdAt: now,
    );
    final templates = await _read();
    templates.add(template);
    await _write(templates);
    return template;
  }

  @override
  Future<void> updateTemplate(ProtocolTemplate template) async {
    final templates = await _read();
    final i = templates.indexWhere((t) => t.id == template.id);
    if (i < 0) {
      throw StateError('Template "${template.id}" not found');
    }
    templates[i] = template;
    await _write(templates);
  }

  @override
  Future<void> deleteTemplate(String id) async {
    final templates = await _read();
    templates.removeWhere((t) => t.id == id);
    await _write(templates);
  }
}
// coverage:ignore-end

// ── In-memory fake for tests ──────────────────────────────────────────────

class InMemoryProtocolRepository implements ProtocolRepository {
  final List<ProtocolTemplate> _templates = [];

  @override
  Future<List<ProtocolTemplate>> listTemplates() async {
    final copy = List<ProtocolTemplate>.from(_templates);
    copy.sort((a, b) => a.name.compareTo(b.name));
    return copy;
  }

  @override
  Future<ProtocolTemplate?> getTemplate(String id) async {
    for (final t in _templates) {
      if (t.id == id) return t;
    }
    return null;
  }

  @override
  Future<ProtocolTemplate> createTemplate({
    required String name,
    String? description,
    required String topicName,
    required int targetTrialCount,
    int sampleRateHz = 100,
  }) async {
    final now = DateTime.now();
    final template = ProtocolTemplate(
      id: now.millisecondsSinceEpoch.toRadixString(16),
      name: name,
      description: description,
      topicName: topicName,
      targetTrialCount: targetTrialCount,
      sampleRateHz: sampleRateHz,
      createdAt: now,
    );
    _templates.add(template);
    return template;
  }

  @override
  Future<void> updateTemplate(ProtocolTemplate template) async {
    final i = _templates.indexWhere((t) => t.id == template.id);
    if (i < 0) {
      throw StateError('Template "${template.id}" not found');
    }
    _templates[i] = template;
  }

  @override
  Future<void> deleteTemplate(String id) async {
    _templates.removeWhere((t) => t.id == id);
  }
}
