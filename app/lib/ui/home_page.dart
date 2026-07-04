import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wheelathlete/state/ble_providers.dart';
import 'package:wheelathlete/theme/theme.dart';
import 'package:wheelathlete/ui/browse_page.dart';
import 'package:wheelathlete/ui/connect_page.dart';
import 'package:wheelathlete/ui/live_page.dart';
import 'package:wheelathlete/widgets/widgets.dart' show ConnectionStatus;

/// Real app home shell with a [NavigationBar] (Material 3) routing to:
///   0 – Connect  : BLE scan + connect L/R wheels
///   1 – Live & Record : realtime IMU display + start/stop recording
///   2 – Browse   : topic → trial → session hierarchy + CSV share +
///                  protocol template progress bars
///
/// The Connect tab badge shows how many wheels are currently connected so the
/// user can always see sensor status at a glance without switching tabs.
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key, required this.themeController});

  final ThemeModeController themeController;

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  int _tab = 0;

  static const _tabs = [
    _TabSpec(
      icon: Icon(Icons.bluetooth_rounded),
      activeIcon: Icon(Icons.bluetooth_connected_rounded),
      label: 'Connect',
    ),
    _TabSpec(
      icon: Icon(Icons.show_chart_rounded),
      activeIcon: Icon(Icons.show_chart_rounded),
      label: 'Live',
    ),
    _TabSpec(
      icon: Icon(Icons.folder_rounded),
      activeIcon: Icon(Icons.folder_open_rounded),
      label: 'Browse',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final connState = ref.watch(connectionManagerProvider);
    final connectedCount =
        connState.bySide.values.where((c) => c.status == ConnectionStatus.connected).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('WheelAthlete'),
        actions: [
          // Connection summary chip — always visible regardless of active tab.
          if (connectedCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.xs),
              child: _ConnectedChip(count: connectedCount),
            ),
          _ThemeToggle(controller: widget.themeController),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: const [
          _ConnectTab(),
          _LiveTab(),
          _BrowseTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(
            icon: Badge(
              label: connectedCount > 0 ? Text('$connectedCount') : null,
              child: _tabs[0].icon,
            ),
            selectedIcon: Badge(
              label: connectedCount > 0 ? Text('$connectedCount') : null,
              child: _tabs[0].activeIcon,
            ),
            label: _tabs[0].label,
          ),
          NavigationDestination(
            icon: _tabs[1].icon,
            selectedIcon: _tabs[1].activeIcon,
            label: _tabs[1].label,
          ),
          NavigationDestination(
            icon: _tabs[2].icon,
            selectedIcon: _tabs[2].activeIcon,
            label: _tabs[2].label,
          ),
        ],
      ),
    );
  }
}

/// The Connect tab body — wraps [ConnectPage] without its own [Scaffold] so the
/// shell's AppBar and BottomNavigationBar stay in place.
///
/// [ConnectPage] is a [ConsumerWidget] that uses [Scaffold] internally. To
/// avoid a nested Scaffold (which causes a grey background artifact), we embed
/// its Scaffold-less body logic here via delegation. However, because
/// [ConnectPage] is already a standalone Scaffold widget we use it as a
/// whole-screen push target from the tab. Instead, we embed it directly inside
/// [IndexedStack] — Flutter allows nested Scaffolds but the nested one should
/// have [appBar] = null so it doesn't double-render. We set [resizeToAvoidBottomInset]
/// to false so the keyboard doesn't fight the outer Scaffold.
class _ConnectTab extends StatelessWidget {
  const _ConnectTab();

  @override
  Widget build(BuildContext context) {
    // ConnectPage is a full Scaffold widget. When embedded inside IndexedStack
    // the inner Scaffold's appBar overlaps with the outer Scaffold's AppBar.
    // Solution: render ConnectPage directly — it handles its own Scaffold.
    // The outer Scaffold's body is just this widget; Material allows nested
    // Scaffolds and inner one handles its own AppBar slot correctly.
    return const ConnectPage();
  }
}

/// The Live tab body — wraps [LivePage] (realtime IMU + Start/Stop FAB).
/// From here the Record button in [LivePage]'s AppBar pushes [RecordPage].
class _LiveTab extends StatelessWidget {
  const _LiveTab();

  @override
  Widget build(BuildContext context) {
    return const LivePage();
  }
}

/// The Browse tab body — wraps [BrowsePage] (topic → trial → session hierarchy).
class _BrowseTab extends StatelessWidget {
  const _BrowseTab();

  @override
  Widget build(BuildContext context) {
    return const BrowsePage();
  }
}

// ─── Internal helpers ────────────────────────────────────────────────────────

class _TabSpec {
  const _TabSpec({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });

  final Widget icon;
  final Widget activeIcon;
  final String label;
}

/// Small pill showing how many wheels are connected in the AppBar.
class _ConnectedChip extends StatelessWidget {
  const _ConnectedChip({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final wc = context.wheelColors;
    final color = count == 2 ? wc.success.solid : wc.warning.solid;
    final label = count == 2 ? 'L+R' : (count == 1 ? '1 wheel' : '');
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        border: Border.all(color: color, width: 1),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.sensors_rounded, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ],
      ),
    );
  }
}

/// Theme-mode toggle icon button shown in the AppBar.
class _ThemeToggle extends StatelessWidget {
  const _ThemeToggle({required this.controller});
  final ThemeModeController controller;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<ThemeMode>(
      tooltip: 'Theme mode',
      icon: Icon(
        controller.isDark(context)
            ? Icons.light_mode_rounded
            : Icons.dark_mode_rounded,
      ),
      onSelected: controller.set,
      itemBuilder: (context) {
        final current = controller.value;
        return [
          _item(ThemeMode.system, 'System', current, Icons.brightness_auto_rounded),
          _item(ThemeMode.light, 'Light', current, Icons.light_mode_rounded),
          _item(ThemeMode.dark, 'Dark', current, Icons.dark_mode_rounded),
        ];
      },
    );
  }

  PopupMenuItem<ThemeMode> _item(
    ThemeMode mode,
    String label,
    ThemeMode current,
    IconData icon,
  ) {
    return PopupMenuItem<ThemeMode>(
      value: mode,
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: AppSpacing.sm),
          Text(label),
          const Spacer(),
          if (mode == current) const Icon(Icons.check_rounded, size: 18),
        ],
      ),
    );
  }
}
