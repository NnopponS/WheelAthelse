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
import 'package:wheelathlete/ui/acquisition_page.dart';
import 'package:wheelathlete/ui/dashboard_page.dart';
import 'package:wheelathlete/ui/diagnostics_page.dart';
import 'package:wheelathlete/ui/model_page.dart';
import 'package:wheelathlete/ui/results_page.dart';
import 'package:wheelathlete/widgets/widgets.dart' show ConnectionStatus;

/// Real app home shell with a [NavigationBar] (Material 3) routing to 5 sections:
///   0 – Dashboard   : sensor summary, board settings, BLE scan/connect
///   1 – Acquisition : live 3-IMU streaming, sync recording, 6 waveform charts
///   2 – Results     : session explorer, multi-select, batch CSV/ZIP export
///   3 – Model       : BiWheel3D trajectory & kinematic analysis
///   4 – Diagnostics : 4-column telemetry matrix [Metric, L, R, C]
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
      icon: Icon(Icons.dashboard_outlined),
      activeIcon: Icon(Icons.dashboard_rounded),
      label: 'Dashboard',
    ),
    _TabSpec(
      icon: Icon(Icons.sensors_outlined),
      activeIcon: Icon(Icons.sensors_rounded),
      label: 'Acquisition',
    ),
    _TabSpec(
      icon: Icon(Icons.folder_outlined),
      activeIcon: Icon(Icons.folder_rounded),
      label: 'Results',
    ),
    _TabSpec(
      icon: Icon(Icons.route_outlined),
      activeIcon: Icon(Icons.route_rounded),
      label: 'Model',
    ),
    _TabSpec(
      icon: Icon(Icons.analytics_outlined),
      activeIcon: Icon(Icons.analytics_rounded),
      label: 'Diagnostics',
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
        children: const [
          DashboardPage(),
          AcquisitionPage(),
          ResultsPage(),
          ModelPage(),
          DiagnosticsPage(),
        ],
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
          NavigationDestination(
            icon: _tabs[3].icon,
            selectedIcon: _tabs[3].activeIcon,
            label: _tabs[3].label,
          ),
          NavigationDestination(
            icon: _tabs[4].icon,
            selectedIcon: _tabs[4].activeIcon,
            label: _tabs[4].label,
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

// ──────────────────────────────────────────────
// Internal helpers
// ──────────────────────────────────────────────

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
