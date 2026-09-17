import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Navigation sections corresponding 1:1 to the Python Research Edition:
/// 0 = Dashboard
/// 1 = Acquisition
/// 2 = Results
/// 3 = Model
/// 4 = Diagnostics
class HomeTabNotifier extends Notifier<int> {
  static const int dashboard = 0;
  static const int acquisition = 1;
  static const int results = 2;
  static const int model = 3;
  static const int diagnostics = 4;

  @override
  int build() => dashboard;

  void setTab(int index) => state = index.clamp(0, 4);
}

final homeTabIndexProvider = NotifierProvider<HomeTabNotifier, int>(
  HomeTabNotifier.new,
);
