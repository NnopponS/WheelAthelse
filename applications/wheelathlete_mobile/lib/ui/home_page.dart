import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wheelathlete/state/ble_providers.dart';
import 'package:wheelathlete/state/home_providers.dart';
import 'package:wheelathlete/state/live_acquisition_providers.dart';
import 'package:wheelathlete/state/record_countdown_providers.dart';
import 'package:wheelathlete/state/recording_providers.dart';
import 'package:wheelathlete/state/update_providers.dart';
import 'package:wheelathlete/theme/theme.dart';
import 'package:wheelathlete/update/app_version.dart';
import 'package:wheelathlete/ui/browse_page.dart';
import 'package:wheelathlete/ui/connect_page.dart';
import 'package:wheelathlete/ui/live_page.dart';
import 'package:wheelathlete/widgets/widgets.dart' show ConnectionStatus;

/// Real app home shell with a [NavigationBar] (Material 3) routing to:
///   0 Ã¢â‚¬â€œ Connect  : BLE scan + connect L/R wheels
///   1 Ã¢â‚¬â€œ Live & Record : realtime IMU display + start/stop recording
///   2 Ã¢â‚¬â€œ Browse   : topic Ã¢â€ â€™ trial Ã¢â€ â€™ session hierarchy + CSV share +
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(mobileUpdateProvider.notifier).startAutomaticChecks();
    });
  }

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
    final tab = ref.watch(homeTabIndexProvider);
    final connectedCount = connState.bySide.values
        .where((c) => c.status == ConnectionStatus.connected)
        .length;
    final update = ref.watch(mobileUpdateProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('WheelAthlete'),
        actions: [
          // Connection summary chip Ã¢â‚¬â€ always visible regardless of active tab.
          if (connectedCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.xs),
              child: _ConnectedChip(count: connectedCount),
            ),
          IconButton(
            key: const Key('softwareUpdateButton'),
            tooltip: update.updateAvailable
                ? 'WheelAthlete update available'
                : 'Software update',
            onPressed: () => _showUpdateDialog(context),
            icon:
                update.status == MobileUpdateStatus.checking ||
                    update.status == MobileUpdateStatus.downloading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Badge(
                    isLabelVisible: update.updateAvailable,
                    child: const Icon(Icons.system_update_alt_rounded),
                  ),
          ),
          _ThemeToggle(controller: widget.themeController),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: IndexedStack(
        index: tab,
        children: const [_ConnectTab(), _LiveTab(), _BrowseTab()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) =>
            ref.read(homeTabIndexProvider.notifier).setTab(i),
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

  bool _acquisitionBusy() {
    final live = ref.read(liveAcquisitionProvider);
    final recording = ref.read(recordingProvider).status;
    final countdown = ref.read(recordCountdownProvider).status;
    final recordingBusy = switch (recording) {
      RecordingStatus.arming ||
      RecordingStatus.awaitingSamples ||
      RecordingStatus.recording ||
      RecordingStatus.stopping => true,
      _ => false,
    };
    final countdownBusy = switch (countdown) {
      RecordCountdownStatus.syncing ||
      RecordCountdownStatus.counting ||
      RecordCountdownStatus.recording => true,
      _ => false,
    };
    return live.active ||
        live.status == LiveAcquisitionStatus.stopping ||
        recordingBusy ||
        countdownBusy;
  }

  Future<void> _runUpdateAction(BuildContext dialogContext) async {
    final state = ref.read(mobileUpdateProvider);
    final notifier = ref.read(mobileUpdateProvider.notifier);
    if (state.status == MobileUpdateStatus.idle ||
        state.status == MobileUpdateStatus.current ||
        state.status == MobileUpdateStatus.error) {
      await notifier.check();
      return;
    }
    if (state.status == MobileUpdateStatus.permissionRequired ||
        state.status == MobileUpdateStatus.readyToInstall) {
      if (_acquisitionBusy()) {
        if (!mounted) return;
        await _showAcquisitionUpdateBlocker(dialogContext);
        return;
      }
      await notifier.installDownloadedAndroidApk();
      return;
    }
    if (state.status == MobileUpdateStatus.available) {
      if (_acquisitionBusy()) {
        if (!mounted) return;
        await _showAcquisitionUpdateBlocker(dialogContext);
        return;
      }
      await notifier.beginUpdate();
    }
  }

  Future<void> _showAcquisitionUpdateBlocker(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stop acquisition first'),
        content: const Text(
          'WheelAthlete will not install an update while Live preview, '
          'countdown, or recording is active. Stop acquisition and try again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _showUpdateDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Consumer(
        builder: (context, dialogRef, _) {
          final update = dialogRef.watch(mobileUpdateProvider);
          final manifest = update.manifest;
          final busy =
              update.status == MobileUpdateStatus.checking ||
              update.status == MobileUpdateStatus.downloading;
          final actionLabel = switch (update.status) {
            MobileUpdateStatus.available =>
              Platform.isIOS ? 'Open update page' : 'Download & install',
            MobileUpdateStatus.permissionRequired ||
            MobileUpdateStatus.readyToInstall => 'Install update',
            MobileUpdateStatus.checking => 'Checking...',
            MobileUpdateStatus.downloading =>
              'Downloading ${(update.progress * 100).round()}%',
            _ => 'Check now',
          };
          return AlertDialog(
            title: const Text('Software update'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Installed: WheelAthlete $wheelAthleteAppVersion (build $wheelAthleteAppBuild)',
                  ),
                  if (manifest != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text('Latest stable: ${manifest.version}'),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    update.message.isEmpty
                        ? 'Updates are verified from the official WheelAthelse GitHub Releases feed.'
                        : update.message,
                  ),
                  if (update.status == MobileUpdateStatus.downloading) ...[
                    const SizedBox(height: AppSpacing.sm),
                    LinearProgressIndicator(value: update.progress),
                  ],
                  if (manifest != null && manifest.notes.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      manifest.notes,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    Platform.isIOS
                        ? 'iOS installation is managed by the App Store/TestFlight.'
                        : 'Android verifies the APK SHA-256 before opening the system installer.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: busy
                    ? null
                    : () => Navigator.of(dialogContext).pop(),
                child: const Text('Close'),
              ),
              FilledButton(
                key: const Key('softwareUpdateActionButton'),
                onPressed: busy ? null : () => _runUpdateAction(dialogContext),
                child: Text(actionLabel),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The Connect tab body Ã¢â‚¬â€ wraps [ConnectPage] without its own [Scaffold] so the
/// shell's AppBar and BottomNavigationBar stay in place.
///
/// [ConnectPage] is a [ConsumerWidget] that uses [Scaffold] internally. To
/// avoid a nested Scaffold (which causes a grey background artifact), we embed
/// its Scaffold-less body logic here via delegation. However, because
/// [ConnectPage] is already a standalone Scaffold widget we use it as a
/// whole-screen push target from the tab. Instead, we embed it directly inside
/// [IndexedStack] Ã¢â‚¬â€ Flutter allows nested Scaffolds but the nested one should
/// have [appBar] = null so it doesn't double-render. We set [resizeToAvoidBottomInset]
/// to false so the keyboard doesn't fight the outer Scaffold.
class _ConnectTab extends StatelessWidget {
  const _ConnectTab();

  @override
  Widget build(BuildContext context) {
    // ConnectPage is a full Scaffold widget. When embedded inside IndexedStack
    // the inner Scaffold's appBar overlaps with the outer Scaffold's AppBar.
    // Solution: render ConnectPage directly Ã¢â‚¬â€ it handles its own Scaffold.
    // The outer Scaffold's body is just this widget; Material allows nested
    // Scaffolds and inner one handles its own AppBar slot correctly.
    return const ConnectPage();
  }
}

/// The Live tab body Ã¢â‚¬â€ wraps [LivePage] (realtime IMU + Start/Stop FAB).
/// From here the Record button in [LivePage]'s AppBar pushes [RecordPage].
class _LiveTab extends StatelessWidget {
  const _LiveTab();

  @override
  Widget build(BuildContext context) {
    return const LivePage();
  }
}

/// The Browse tab body Ã¢â‚¬â€ wraps [BrowsePage] (topic Ã¢â€ â€™ trial Ã¢â€ â€™ session hierarchy).
class _BrowseTab extends StatelessWidget {
  const _BrowseTab();

  @override
  Widget build(BuildContext context) {
    return const BrowsePage();
  }
}

// Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬ Internal helpers Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

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
          _item(
            ThemeMode.system,
            'System',
            current,
            Icons.brightness_auto_rounded,
          ),
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
