import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Index of the currently selected tab in the app's [NavigationBar].
///
/// 0 = Connect, 1 = Live, 2 = Browse.
///
/// This is global UI state so that any screen can switch the user's current
/// tab (e.g. the Live page's AppBar Browse button jumps to Browse instead of
/// pushing a second Browse page on the navigation stack, which was out of sync
/// with the bottom nav).
class HomeTabNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void setTab(int index) => state = index;
}

final homeTabIndexProvider = NotifierProvider<HomeTabNotifier, int>(
  HomeTabNotifier.new,
);
