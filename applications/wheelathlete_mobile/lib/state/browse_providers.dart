import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wheelathlete/records/storage_repository.dart';
import 'package:wheelathlete/records/session_model.dart';
import 'package:wheelathlete/state/ble_providers.dart';

final topicsProvider = FutureProvider<List<TopicEntry>>((ref) async {
  final storage = ref.watch(storageRepositoryProvider);
  return storage.listTopics();
});

final trialsProvider = FutureProvider.family<List<int>, String>((
  ref,
  topic,
) async {
  final storage = ref.watch(storageRepositoryProvider);
  return storage.listTrials(topic);
});

// arg is formatted as "topic:trialNumber"
final sessionsProvider = FutureProvider.family<List<SessionMeta>, String>((
  ref,
  arg,
) async {
  final parts = arg.split(':');
  final topic = parts[0];
  final trial = int.parse(parts[1]);
  final storage = ref.watch(storageRepositoryProvider);
  return storage.listSessions(topic, trial);
});

/// Search query for the Browse page (Phase 3, §7 Search/filter on Browse).
///
/// A single provider is shared between the Topic list and the Session list
/// views. It is reset to an empty string whenever the user navigates between
/// hierarchy levels (see `BrowsePage` navigation callbacks), so each level
/// starts with a clean search state.
///
/// Filtering is performed in-memory on the already-loaded list — no storage
/// query change. An empty string means "no filter" (show all items).
class BrowseSearchNotifier extends Notifier<String> {
  @override
  String build() => '';

  /// Sets the current search query.
  void set(String query) => state = query;

  /// Clears the search query (back to empty string = no filter).
  void clear() => state = '';
}

final browseSearchProvider = NotifierProvider<BrowseSearchNotifier, String>(
  BrowseSearchNotifier.new,
);

/// Active tag filter for the Browse page Session list (Phase 3, §7).
///
/// When non-null, only sessions whose `tags` list contains this value are
/// shown. Tapping a tag chip toggles this between the tag and `null`.
/// Combined with [browseSearchProvider] using AND logic: a session must match
/// both the search query (if any) and the tag filter (if any) to appear.
class BrowseTagFilterNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  /// Sets the active tag filter, or clears it when [tag] is null.
  void set(String? tag) => state = tag;

  /// Toggles the tag filter: if [tag] is already selected it is cleared,
  /// otherwise it becomes the active filter.
  void toggle(String tag) => state = state == tag ? null : tag;

  /// Clears the tag filter (back to null = no filter).
  void clear() => state = null;
}

final browseTagFilterProvider =
    NotifierProvider<BrowseTagFilterNotifier, String?>(
      BrowseTagFilterNotifier.new,
    );

/// Shared topic to open in the Browse tab (Phase 3, §8 Experiment tracker).
///
/// The Experiment tracker dashboard sets this before switching to the Browse
/// tab (index 2); [BrowsePage] reads it on init to pre-select that topic, then
/// clears it. Using a shared provider keeps the cross-tab navigation decoupled —
/// the dashboard does not need a direct reference to the Browse page's state.
class SelectedTopicNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  /// Sets the topic to open in Browse.
  void set(String? topic) => state = topic;

  /// Clears the pending topic (call after Browse has consumed it).
  void clear() => state = null;
}

final selectedTopicProvider = NotifierProvider<SelectedTopicNotifier, String?>(
  SelectedTopicNotifier.new,
);

void invalidateBrowseStorage(WidgetRef ref, {String? topic, int? trialNumber}) {
  ref.invalidate(topicsProvider);
  if (topic != null) {
    ref.invalidate(trialsProvider(topic));
    if (trialNumber != null) {
      ref.invalidate(sessionsProvider('$topic:$trialNumber'));
    }
  }
}
