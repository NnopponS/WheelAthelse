import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wheelathlete/records/protocol_repository.dart';
import 'package:wheelathlete/records/protocol_template.dart';

/// Constructs the production [ProtocolRepository]. Override in tests with an
/// [InMemoryProtocolRepository] via `protocolRepositoryProvider.overrideWith`.
final protocolRepositoryProvider = Provider<ProtocolRepository>(
  (ref) => PathProviderProtocolRepository(),
);

/// Loads all protocol templates (sorted by name). Refreshed by
/// [protocolTemplateNotifierProvider] after any CRUD mutation.
final protocolTemplatesProvider =
    FutureProvider<List<ProtocolTemplate>>((ref) async {
  final repo = ref.watch(protocolRepositoryProvider);
  return repo.listTemplates();
});

/// State surfaced to the UI for the template CRUD flow.
class ProtocolTemplateNotifierState {
  const ProtocolTemplateNotifierState({
    this.templates = const [],
    this.loading = false,
    this.error,
  });

  final List<ProtocolTemplate> templates;
  final bool loading;
  final String? error;

  ProtocolTemplateNotifierState copyWith({
    List<ProtocolTemplate>? templates,
    bool? loading,
    Object? error = _unset,
  }) =>
      ProtocolTemplateNotifierState(
        templates: templates ?? this.templates,
        loading: loading ?? this.loading,
        error: identical(error, _unset) ? this.error : error as String?,
      );

  static const Object _unset = Object();
}

/// Notifier for protocol template CRUD operations. Each mutation reloads the
/// full list from the repository and keeps [protocolTemplatesProvider] in sync
/// via [ref.invalidateSelf].
class ProtocolTemplateNotifier
    extends Notifier<ProtocolTemplateNotifierState> {
  @override
  ProtocolTemplateNotifierState build() {
    // Kick off the initial load.
    _load();
    return const ProtocolTemplateNotifierState(loading: true);
  }

  ProtocolRepository get _repo => ref.read(protocolRepositoryProvider);

  Future<void> _load() async {
    try {
      final templates = await _repo.listTemplates();
      if (!ref.mounted) return;
      state = ProtocolTemplateNotifierState(templates: templates);
    } on Object catch (e) {
      if (!ref.mounted) return;
      state = ProtocolTemplateNotifierState(error: '$e');
    }
  }

  /// Reloads templates from the repository.
  Future<void> refresh() async {
    if (!ref.mounted) return;
    state = state.copyWith(loading: true, error: null);
    await _load();
    ref.invalidate(protocolTemplatesProvider);
  }

  /// Creates a new template and reloads the list. Returns the created
  /// template (with its generated id).
  Future<ProtocolTemplate> createTemplate({
    required String name,
    String? description,
    required String topicName,
    required int targetTrialCount,
    int sampleRateHz = 100,
  }) async {
    final template = await _repo.createTemplate(
      name: name,
      description: description,
      topicName: topicName,
      targetTrialCount: targetTrialCount,
      sampleRateHz: sampleRateHz,
    );
    await refresh();
    return template;
  }

  /// Updates an existing template and reloads the list.
  Future<void> updateTemplate(ProtocolTemplate template) async {
    await _repo.updateTemplate(template);
    await refresh();
  }

  /// Deletes the template with [id] and reloads the list.
  Future<void> deleteTemplate(String id) async {
    await _repo.deleteTemplate(id);
    await refresh();
  }
}

final protocolTemplateNotifierProvider =
    NotifierProvider<ProtocolTemplateNotifier, ProtocolTemplateNotifierState>(
  ProtocolTemplateNotifier.new,
);
