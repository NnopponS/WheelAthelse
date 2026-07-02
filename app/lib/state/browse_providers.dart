import 'package:flutter_riverpod/flutter_riverpod.dart';

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

final browseSearchProvider =
    NotifierProvider<BrowseSearchNotifier, String>(
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
