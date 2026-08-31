import 'dart:async';
import 'dart:io';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wheelathlete/desktop/daemon_client.dart';
import 'package:wheelathlete/desktop/desktop_acquisition_providers.dart';
import 'package:wheelathlete/state/protocol_providers.dart';
import 'package:wheelathlete/theme/theme.dart';
import 'package:wheelathlete/ui/browse_page.dart';
import 'package:wheelathlete/ui/experiment_tracker_page.dart';

class DesktopHomePage extends ConsumerStatefulWidget {
  const DesktopHomePage({
    super.key,
    required this.themeController,
    this.autoConnect = true,
  });

  final ThemeModeController themeController;
  final bool autoConnect;

  @override
  ConsumerState<DesktopHomePage> createState() => _DesktopHomePageState();
}

class _DesktopHomePageState extends ConsumerState<DesktopHomePage> {
  int _index = 0;
  bool _launchingDaemon = false;

  static const _destinations = <_DesktopDestination>[
    _DesktopDestination('Dashboard', Icons.dashboard_outlined, Icons.dashboard),
    _DesktopDestination(
      'Connect',
      Icons.bluetooth_searching,
      Icons.bluetooth_connected,
    ),
    _DesktopDestination(
      'Live',
      Icons.monitor_heart_outlined,
      Icons.monitor_heart,
    ),
    _DesktopDestination(
      'Record',
      Icons.fiber_manual_record_outlined,
      Icons.fiber_manual_record,
    ),
    _DesktopDestination('Experiments', Icons.science_outlined, Icons.science),
    _DesktopDestination('Sessions', Icons.folder_outlined, Icons.folder),
    _DesktopDestination(
      'Diagnostics',
      Icons.troubleshoot_outlined,
      Icons.troubleshoot,
    ),
  ];

  @override
  void initState() {
    super.initState();
    if (widget.autoConnect) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await ref.read(desktopAcquisitionProvider.notifier).connect();
        await ref.read(desktopAcquisitionProvider.notifier).loadSessions();
      });
    }
  }

  Future<void> _launchSourceDaemon() async {
    if (_launchingDaemon) return;
    setState(() => _launchingDaemon = true);
    try {
      final cwd = Directory.current;
      String? root;
      if (File(
        '${cwd.path}${Platform.pathSeparator}tools${Platform.pathSeparator}pc_acquisition${Platform.pathSeparator}daemon.py',
      ).existsSync()) {
        root = cwd.path;
      } else if (File(
        '${cwd.parent.path}${Platform.pathSeparator}tools${Platform.pathSeparator}pc_acquisition${Platform.pathSeparator}daemon.py',
      ).existsSync()) {
        root = cwd.parent.path;
      }
      if (root == null) {
        throw StateError(
          'Source daemon was not found. Start the packaged/source acquisition daemon and reconnect.',
        );
      }
      await DesktopDaemonProcess.launch(workingDirectory: root);
      await Future<void>.delayed(const Duration(milliseconds: 900));
      await ref.read(desktopAcquisitionProvider.notifier).connect();
      await ref.read(desktopAcquisitionProvider.notifier).loadSessions();
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to launch daemon: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _launchingDaemon = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(desktopAcquisitionProvider);
    final pages = <Widget>[
      _DesktopDashboard(onNavigate: (index) => setState(() => _index = index)),
      _DesktopConnectPage(
        onLaunchDaemon: _launchSourceDaemon,
        launchingDaemon: _launchingDaemon,
      ),
      const _DesktopLivePage(),
      const _DesktopRecordPage(),
      ExperimentTrackerPage(onOpenTopic: (_) => setState(() => _index = 5)),
      const _DesktopSessionsPage(),
      const _DesktopDiagnosticsPage(),
    ];

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            NavigationRail(
              extended: MediaQuery.sizeOf(context).width >= 1180,
              selectedIndex: _index,
              onDestinationSelected: (value) => setState(() => _index = value),
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Column(
                  children: [
                    const Icon(Icons.wheelchair_pickup_rounded, size: 34),
                    const SizedBox(height: AppSpacing.xs),
                    if (MediaQuery.sizeOf(context).width >= 1180)
                      Text(
                        'WheelAthlete PC',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                  ],
                ),
              ),
              trailing: Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _DaemonRailStatus(connected: state.connected),
                    _DesktopThemeToggle(controller: widget.themeController),
                    const SizedBox(height: AppSpacing.md),
                  ],
                ),
              ),
              destinations: [
                for (final destination in _destinations)
                  NavigationRailDestination(
                    icon: Icon(destination.icon),
                    selectedIcon: Icon(destination.selectedIcon),
                    label: Text(destination.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: Column(
                children: [
                  _DesktopHeader(
                    title: _destinations[_index].label,
                    state: state,
                    onReconnect: () =>
                        ref.read(desktopAcquisitionProvider.notifier).connect(),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: IndexedStack(index: _index, children: pages),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopDestination {
  const _DesktopDestination(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class _DesktopHeader extends StatelessWidget {
  const _DesktopHeader({
    required this.title,
    required this.state,
    required this.onReconnect,
  });

  final String title;
  final DesktopAcquisitionState state;
  final VoidCallback onReconnect;

  @override
  Widget build(BuildContext context) {
    final boards = _boards(state.status);
    final connectedBoards = boards.values
        .where((value) => value['connected'] == true)
        .length;
    return SizedBox(
      height: 64,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Row(
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const Spacer(),
            if (state.status['recording'] == true)
              const Padding(
                padding: EdgeInsets.only(right: AppSpacing.sm),
                child: Chip(
                  avatar: Icon(Icons.fiber_manual_record, size: 16),
                  label: Text('RECORDING'),
                ),
              ),
            Chip(
              avatar: Icon(
                state.connected ? Icons.check_circle : Icons.cloud_off,
                size: 16,
              ),
              label: Text(
                state.connected
                    ? 'Daemon online · $connectedBoards/2 boards'
                    : 'Daemon offline',
              ),
            ),
            if (!state.connected)
              TextButton.icon(
                onPressed: state.connecting ? null : onReconnect,
                icon: state.connecting
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                label: const Text('Reconnect'),
              ),
          ],
        ),
      ),
    );
  }
}

class _DaemonRailStatus extends StatelessWidget {
  const _DaemonRailStatus({required this.connected});
  final bool connected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Tooltip(
        message: connected
            ? 'Acquisition daemon online'
            : 'Acquisition daemon offline',
        child: Icon(
          connected ? Icons.link_rounded : Icons.link_off_rounded,
          color: connected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.error,
        ),
      ),
    );
  }
}

class _DesktopThemeToggle extends StatelessWidget {
  const _DesktopThemeToggle({required this.controller});
  final ThemeModeController controller;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<ThemeMode>(
      tooltip: 'Theme mode',
      icon: const Icon(Icons.contrast_rounded),
      onSelected: controller.set,
      itemBuilder: (context) => [
        for (final entry in const [
          (ThemeMode.system, 'System', Icons.brightness_auto_rounded),
          (ThemeMode.light, 'Light', Icons.light_mode_rounded),
          (ThemeMode.dark, 'Dark', Icons.dark_mode_rounded),
        ])
          PopupMenuItem<ThemeMode>(
            value: entry.$1,
            child: Row(
              children: [
                Icon(entry.$3),
                const SizedBox(width: AppSpacing.sm),
                Text(entry.$2),
                const Spacer(),
                if (controller.value == entry.$1)
                  const Icon(Icons.check, size: 18),
              ],
            ),
          ),
      ],
    );
  }
}

class _DesktopDashboard extends ConsumerWidget {
  const _DesktopDashboard({required this.onNavigate});
  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(desktopAcquisitionProvider);
    final boards = _boards(state.status);
    final incomplete =
        (state.status['incomplete_sessions'] as List?) ?? const [];
    return _DesktopScroll(
      children: [
        _SectionTitle(
          title: 'Research acquisition overview',
          subtitle:
              'Raw BLE ingestion, synchronization and journaling stay in the Python daemon.',
          trailing: FilledButton.icon(
            onPressed: state.connected
                ? () => ref
                      .read(desktopAcquisitionProvider.notifier)
                      .refreshStatus()
                : null,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
          ),
        ),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            _MetricCard(
              title: 'Daemon',
              value: state.connected ? 'ONLINE' : 'OFFLINE',
              detail: '${state.status['journal_root'] ?? 'Connect to begin'}',
              icon: Icons.dns_rounded,
            ),
            _MetricCard(
              title: 'Recording',
              value: state.recording ? 'ACTIVE' : 'IDLE',
              detail: '${state.status['session_id'] ?? 'No active session'}',
              icon: Icons.fiber_manual_record,
            ),
            _MetricCard(
              title: 'Incomplete',
              value: '${incomplete.length}',
              detail: incomplete.isEmpty
                  ? 'No crash-recovery items'
                  : 'Recovery available',
              icon: Icons.health_and_safety_outlined,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('Boards', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpacing.sm),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth >= 900
                ? (constraints.maxWidth - AppSpacing.md) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: [
                SizedBox(
                  width: width,
                  child: _BoardSummaryCard(
                    side: 'L',
                    board: boards['L'] ?? const {},
                  ),
                ),
                SizedBox(
                  width: width,
                  child: _BoardSummaryCard(
                    side: 'R',
                    board: boards['R'] ?? const {},
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('Quick actions', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            FilledButton.tonalIcon(
              onPressed: () => onNavigate(1),
              icon: const Icon(Icons.bluetooth_searching),
              label: const Text('Connect sensors'),
            ),
            FilledButton.tonalIcon(
              onPressed: () => onNavigate(3),
              icon: const Icon(Icons.fiber_manual_record),
              label: const Text('New recording'),
            ),
            FilledButton.tonalIcon(
              onPressed: () => onNavigate(6),
              icon: const Icon(Icons.troubleshoot),
              label: const Text('Open diagnostics'),
            ),
          ],
        ),
        if (state.error != null) ...[
          const SizedBox(height: AppSpacing.lg),
          _ErrorBanner(message: state.error!),
        ],
      ],
    );
  }
}

class _DesktopConnectPage extends ConsumerWidget {
  const _DesktopConnectPage({
    required this.onLaunchDaemon,
    required this.launchingDaemon,
  });

  final Future<void> Function() onLaunchDaemon;
  final bool launchingDaemon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(desktopAcquisitionProvider);
    final notifier = ref.read(desktopAcquisitionProvider.notifier);
    final boards = _boards(state.status);

    return _DesktopScroll(
      children: [
        if (!state.connected)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Acquisition daemon is offline',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  const Text(
                    'The Windows UI never talks to BLE directly. Start the dedicated Python/Bleak daemon, then reconnect.',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.sm,
                    children: [
                      FilledButton.icon(
                        onPressed: state.connecting ? null : notifier.connect,
                        icon: const Icon(Icons.link),
                        label: const Text('Reconnect'),
                      ),
                      OutlinedButton.icon(
                        onPressed: launchingDaemon ? null : onLaunchDaemon,
                        icon: launchingDaemon
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.terminal),
                        label: const Text('Launch source daemon'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        _SectionTitle(
          title: 'Left / Right sensors',
          subtitle:
              'Connection quality is based on the data path, not RSSI alone.',
          trailing: FilledButton.icon(
            onPressed: !state.connected || state.scanning
                ? null
                : notifier.scan,
            icon: state.scanning
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.bluetooth_searching),
            label: Text(state.scanning ? 'Scanning…' : 'Scan'),
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth >= 900
                ? (constraints.maxWidth - AppSpacing.md) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: [
                SizedBox(
                  width: width,
                  child: _ConnectedBoardCard(
                    side: 'L',
                    board: boards['L'] ?? const {},
                  ),
                ),
                SizedBox(
                  width: width,
                  child: _ConnectedBoardCard(
                    side: 'R',
                    board: boards['R'] ?? const {},
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Discovered devices',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: AppSpacing.sm),
        if (state.devices.isEmpty)
          const _EmptyDesktopState(
            icon: Icons.bluetooth_disabled,
            title: 'No scan results yet',
            message:
                'Run a scan while both XIAO boards are powered and within range.',
          )
        else
          for (final device in state.devices)
            Card(
              child: ListTile(
                leading: const Icon(Icons.sensors),
                title: Text('${device['name'] ?? 'WheelAthlete sensor'}'),
                subtitle: Text(
                  '${device['device_id']} · RSSI ${device['rssi'] ?? '—'} dBm',
                ),
                trailing: FilledButton.tonal(
                  onPressed: () async {
                    try {
                      await notifier.connectDevice('${device['device_id']}');
                    } on Object catch (error) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Connect failed: $error')),
                        );
                      }
                    }
                  },
                  child: const Text('Connect'),
                ),
              ),
            ),
        if (state.error != null) ...[
          const SizedBox(height: AppSpacing.md),
          _ErrorBanner(message: state.error!),
        ],
      ],
    );
  }
}

class _ConnectedBoardCard extends ConsumerWidget {
  const _ConnectedBoardCard({required this.side, required this.board});
  final String side;
  final Map<String, dynamic> board;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connected = board['connected'] == true;
    final info = _map(board['info']);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(child: Text(side)),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        connected
                            ? '${info['name'] ?? 'Wheel $side'}'
                            : 'Wheel $side',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(connected ? 'Connected' : 'Not connected'),
                    ],
                  ),
                ),
                Icon(
                  connected ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: connected
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).disabledColor,
                ),
              ],
            ),
            const Divider(height: AppSpacing.lg),
            _KeyValue('Firmware', info['firmware']),
            _KeyValue('Device ID', board['device_id']),
            _KeyValue('Hardware model', info['hardware_model']),
            _KeyValue(
              'RSSI',
              info['rssi'] == null ? null : '${info['rssi']} dBm',
            ),
            _KeyValue(
              'Battery',
              info['battery_percent'] == null
                  ? null
                  : '${info['battery_percent']}%',
            ),
            _KeyValue('MTU', board['mtu']),
            _KeyValue(
              'Configured rate',
              info['sample_rate_hz'] == null
                  ? null
                  : '${info['sample_rate_hz']} Hz',
            ),
            _KeyValue('Received rate', _hz(board['samples_hz'])),
            _KeyValue('Seq gaps', board['sequence_gaps']),
            _KeyValue(
              'Queue',
              '${board['queue_depth'] ?? 0} / high ${board['queue_high_water'] ?? 0}',
            ),
            if (connected) ...[
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue:
                          (info['sample_rate_hz'] as num?)?.toInt() ?? 100,
                      decoration: const InputDecoration(
                        labelText: 'Sample rate',
                      ),
                      items: const [50, 100, 200]
                          .map(
                            (rate) => DropdownMenuItem(
                              value: rate,
                              child: Text('$rate Hz'),
                            ),
                          )
                          .toList(),
                      onChanged: (rate) {
                        if (rate != null) {
                          unawaited(
                            ref
                                .read(desktopAcquisitionProvider.notifier)
                                .configureSide(side, sampleRateHz: rate),
                          );
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  OutlinedButton.icon(
                    onPressed: () => ref
                        .read(desktopAcquisitionProvider.notifier)
                        .disconnectSide(side),
                    icon: const Icon(Icons.link_off),
                    label: const Text('Disconnect'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DesktopLivePage extends ConsumerStatefulWidget {
  const _DesktopLivePage();

  @override
  ConsumerState<_DesktopLivePage> createState() => _DesktopLivePageState();
}

class _DesktopLivePageState extends ConsumerState<_DesktopLivePage> {
  bool _busy = false;
  bool _liveStarted = false;

  Future<void> _startLive() async {
    if (_busy) return;
    setState(() => _busy = true);
    final notifier = ref.read(desktopAcquisitionProvider.notifier);
    final boards = _boards(ref.read(desktopAcquisitionProvider).status);
    final sides = boards.entries
        .where((entry) => entry.value['connected'] == true)
        .map((entry) => entry.key)
        .toList();
    try {
      if (sides.isEmpty) throw StateError('Connect at least one wheel first');
      for (final side in sides) {
        await notifier.command('sync', {'side': side, 'count': 5});
      }
      await notifier.command('arm', {'sides': sides});
      await notifier.command('scheduled_start', {
        'sides': sides,
        'lead_time_s': 1.5,
        'ack_timeout_s': 1.0,
      }, const Duration(seconds: 15));
      await notifier.refreshStatus();
      if (mounted) setState(() => _liveStarted = true);
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Live start failed: $error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stopLive() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(desktopAcquisitionProvider.notifier)
          .command('stop', const {}, const Duration(seconds: 15));
      await ref.read(desktopAcquisitionProvider.notifier).refreshStatus();
      if (mounted) setState(() => _liveStarted = false);
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Live stop failed: $error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(desktopAcquisitionProvider);
    final boards = _boards(state.status);
    return _DesktopScroll(
      children: [
        _SectionTitle(
          title: 'Throttled live preview',
          subtitle:
              'Graphs update from the daemon preview channel (~10 Hz); raw 50/100/200 Hz samples never cross into Flutter.',
          trailing: FilledButton.icon(
            onPressed: !state.connected || _busy
                ? null
                : (_liveStarted ? _stopLive : _startLive),
            icon: _busy
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(_liveStarted ? Icons.stop : Icons.play_arrow),
            label: Text(_liveStarted ? 'Stop live' : 'Start live'),
          ),
        ),
        for (final side in const ['L', 'R']) ...[
          _LiveWheelPanel(
            side: side,
            board: boards[side] ?? const {},
            history: state.previewHistoryBySide[side] ?? const [],
          ),
          const SizedBox(height: AppSpacing.md),
        ],
      ],
    );
  }
}

class _LiveWheelPanel extends StatelessWidget {
  const _LiveWheelPanel({
    required this.side,
    required this.board,
    required this.history,
  });

  final String side;
  final Map<String, dynamic> board;
  final List<DesktopPreviewSample> history;

  @override
  Widget build(BuildContext context) {
    final info = _map(board['info']);
    final accelScale = (info['accel_scale'] as num?)?.toDouble() ?? 1.0;
    final gyroScale = (info['gyro_scale'] as num?)?.toDouble() ?? 1.0;
    final latest = history.isEmpty ? null : history.last;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(child: Text(side)),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'Wheel $side',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                _SmallMetric('Hz', _hz(board['samples_hz'])),
                _SmallMetric('Samples', '${board['samples'] ?? 0}'),
                _SmallMetric('Gaps', '${board['sequence_gaps'] ?? 0}'),
                _SmallMetric('Queue', '${board['queue_depth'] ?? 0}'),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (latest == null)
              const SizedBox(
                height: 180,
                child: _EmptyDesktopState(
                  icon: Icons.show_chart,
                  title: 'Waiting for preview samples',
                  message: 'Start live or a recording to see IMU data.',
                ),
              )
            else ...[
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  _ValueTile('AX', latest.ax * accelScale, 'g'),
                  _ValueTile('AY', latest.ay * accelScale, 'g'),
                  _ValueTile('AZ', latest.az * accelScale, 'g'),
                  _ValueTile('GX', latest.gx * gyroScale, '°/s'),
                  _ValueTile('GY', latest.gy * gyroScale, '°/s'),
                  _ValueTile('GZ', latest.gz * gyroScale, '°/s'),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth >= 800
                      ? (constraints.maxWidth - AppSpacing.md) / 2
                      : constraints.maxWidth;
                  return Wrap(
                    spacing: AppSpacing.md,
                    runSpacing: AppSpacing.md,
                    children: [
                      SizedBox(
                        width: width,
                        height: 220,
                        child: _PreviewChart(
                          title: 'Acceleration (g)',
                          history: history,
                          values: (sample) => [
                            sample.ax * accelScale,
                            sample.ay * accelScale,
                            sample.az * accelScale,
                          ],
                        ),
                      ),
                      SizedBox(
                        width: width,
                        height: 220,
                        child: _PreviewChart(
                          title: 'Gyroscope (°/s)',
                          history: history,
                          values: (sample) => [
                            sample.gx * gyroScale,
                            sample.gy * gyroScale,
                            sample.gz * gyroScale,
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PreviewChart extends StatelessWidget {
  const _PreviewChart({
    required this.title,
    required this.history,
    required this.values,
  });

  final String title;
  final List<DesktopPreviewSample> history;
  final List<double> Function(DesktopPreviewSample) values;

  @override
  Widget build(BuildContext context) {
    final source = history.length > 120
        ? history.sublist(history.length - 120)
        : history;
    if (source.length < 2) return Center(child: Text(title));
    final firstNs = source.first.pcNs;
    List<FlSpot> series(int axis) => [
      for (final sample in source)
        FlSpot((sample.pcNs - firstNs) / 1e9, values(sample)[axis]),
    ];
    final colors = [
      Theme.of(context).colorScheme.primary,
      Theme.of(context).colorScheme.secondary,
      Theme.of(context).colorScheme.tertiary,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: AppSpacing.xs),
        Expanded(
          child: LineChart(
            LineChartData(
              clipData: const FlClipData.all(),
              titlesData: const FlTitlesData(
                topTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
              ),
              borderData: FlBorderData(show: true),
              gridData: const FlGridData(show: true),
              lineTouchData: const LineTouchData(enabled: false),
              lineBarsData: [
                for (var axis = 0; axis < 3; axis++)
                  LineChartBarData(
                    spots: series(axis),
                    isCurved: false,
                    dotData: const FlDotData(show: false),
                    barWidth: 1.5,
                    color: colors[axis],
                  ),
              ],
            ),
            duration: Duration.zero,
          ),
        ),
      ],
    );
  }
}

class _DesktopRecordPage extends ConsumerStatefulWidget {
  const _DesktopRecordPage();

  @override
  ConsumerState<_DesktopRecordPage> createState() => _DesktopRecordPageState();
}

class _DesktopRecordPageState extends ConsumerState<_DesktopRecordPage> {
  final _athlete = TextEditingController();
  final _topic = TextEditingController();
  final _notes = TextEditingController();
  int _trial = 1;
  int _rate = 100;
  String? _templateId;
  bool _busy = false;
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _athlete.dispose();
    _topic.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(desktopAcquisitionProvider.notifier).startRecord({
        'athlete': _athlete.text.trim(),
        'topic': _topic.text.trim(),
        'trial_number': _trial,
        'notes': _notes.text.trim(),
        'sample_rate_hz': _rate,
        if (_templateId != null) 'protocol_template_id': _templateId,
      });
      _stopwatch
        ..reset()
        ..start();
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Recording start failed: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await ref
          .read(desktopAcquisitionProvider.notifier)
          .endRecord();
      _stopwatch.stop();
      _timer?.cancel();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Saved ${result['session_id']} · quality ${result['quality']}',
            ),
          ),
        );
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Recording stop/finalize failed: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(desktopAcquisitionProvider);
    final templates = ref.watch(protocolTemplatesProvider);
    final boards = _boards(state.status);
    final connectedSides = boards.entries
        .where((e) => e.value['connected'] == true)
        .map((e) => e.key)
        .toList();
    final recording = state.recording;
    final result = state.lastRecordingResult;

    return _DesktopScroll(
      children: [
        _SectionTitle(
          title: 'Research recording',
          subtitle:
              'Pre-sync → one shared future T0 → stream only → safe STOP → post-sync → QC.',
          trailing: Chip(
            avatar: Icon(
              recording ? Icons.fiber_manual_record : Icons.circle_outlined,
              size: 16,
            ),
            label: Text(
              recording ? _formatDuration(_stopwatch.elapsed) : 'Idle',
            ),
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            final form = Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  children: [
                    TextField(
                      controller: _athlete,
                      enabled: !recording,
                      decoration: const InputDecoration(labelText: 'Athlete'),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextField(
                      controller: _topic,
                      enabled: !recording,
                      decoration: const InputDecoration(
                        labelText: 'Topic / experiment',
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: _trial,
                            decoration: const InputDecoration(
                              labelText: 'Trial',
                            ),
                            items: [
                              for (var value = 1; value <= 30; value++)
                                DropdownMenuItem(
                                  value: value,
                                  child: Text('$value'),
                                ),
                            ],
                            onChanged: recording
                                ? null
                                : (value) =>
                                      setState(() => _trial = value ?? 1),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: _rate,
                            decoration: const InputDecoration(
                              labelText: 'Sample rate',
                            ),
                            items: const [50, 100, 200]
                                .map(
                                  (value) => DropdownMenuItem(
                                    value: value,
                                    child: Text('$value Hz'),
                                  ),
                                )
                                .toList(),
                            onChanged: recording
                                ? null
                                : (value) =>
                                      setState(() => _rate = value ?? 100),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    templates.when(
                      loading: () => const LinearProgressIndicator(),
                      error: (_, _) => const SizedBox.shrink(),
                      data: (items) => DropdownButtonFormField<String?>(
                        initialValue: _templateId,
                        decoration: const InputDecoration(
                          labelText: 'Protocol template',
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('Custom / none'),
                          ),
                          for (final item in items)
                            DropdownMenuItem<String?>(
                              value: item.id,
                              child: Text(item.name),
                            ),
                        ],
                        onChanged: recording
                            ? null
                            : (value) {
                                setState(() => _templateId = value);
                                if (value != null) {
                                  final template = items
                                      .where((item) => item.id == value)
                                      .firstOrNull;
                                  if (template != null) {
                                    _topic.text = template.topicName;
                                    _rate = template.sampleRateHz;
                                  }
                                }
                              },
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextField(
                      controller: _notes,
                      enabled: !recording,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(labelText: 'Notes'),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed:
                            !state.connected || connectedSides.isEmpty || _busy
                            ? null
                            : (recording ? _stop : _start),
                        icon: _busy
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                recording
                                    ? Icons.stop
                                    : Icons.fiber_manual_record,
                              ),
                        label: Text(
                          recording
                              ? 'Stop and validate recording'
                              : 'Sync, countdown and record',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
            final quality = _RecordingQualityPanel(
              state: state,
              connectedSides: connectedSides,
              finalResult: result,
            );
            if (!wide) {
              return Column(
                children: [
                  form,
                  const SizedBox(height: AppSpacing.md),
                  quality,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: form),
                const SizedBox(width: AppSpacing.md),
                Expanded(flex: 2, child: quality),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _RecordingQualityPanel extends StatelessWidget {
  const _RecordingQualityPanel({
    required this.state,
    required this.connectedSides,
    required this.finalResult,
  });

  final DesktopAcquisitionState state;
  final List<String> connectedSides;
  final Map<String, dynamic>? finalResult;

  @override
  Widget build(BuildContext context) {
    final boards = _boards(state.status);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Data quality', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            _KeyValue(
              'Connected wheels',
              connectedSides.isEmpty ? 'None' : connectedSides.join(' + '),
            ),
            for (final side in connectedSides) ...[
              const Divider(),
              Text(
                'Wheel $side',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              _KeyValue('Received', boards[side]?['samples']),
              _KeyValue('Effective rate', _hz(boards[side]?['samples_hz'])),
              _KeyValue('Sequence gaps', boards[side]?['sequence_gaps']),
              _KeyValue('Duplicates', boards[side]?['duplicates']),
              _KeyValue('Out of order', boards[side]?['out_of_order']),
              _KeyValue('Queue high-water', boards[side]?['queue_high_water']),
              _KeyValue(
                'Host overflow',
                boards[side]?['queue_overflow_faults'],
              ),
            ],
            if (finalResult != null) ...[
              const Divider(height: AppSpacing.lg),
              Text(
                'Last finalized session',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              _KeyValue('Quality', finalResult!['quality']),
              _KeyValue(
                'Duration',
                finalResult!['duration_s'] == null
                    ? null
                    : '${(finalResult!['duration_s'] as num).toStringAsFixed(2)} s',
              ),
              _KeyValue('Journal', finalResult!['journal_path']),
            ],
          ],
        ),
      ),
    );
  }
}

class _DesktopSessionsPage extends ConsumerStatefulWidget {
  const _DesktopSessionsPage();

  @override
  ConsumerState<_DesktopSessionsPage> createState() =>
      _DesktopSessionsPageState();
}

class _DesktopSessionsPageState extends ConsumerState<_DesktopSessionsPage> {
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(desktopAcquisitionProvider.notifier).loadSessions();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(desktopAcquisitionProvider);
    final filtered = state.sessions.where((session) {
      final haystack = [
        session['session_id'],
        session['athlete'],
        session['topic'],
        session['quality'],
        session['notes'],
      ].join(' ').toLowerCase();
      return haystack.contains(_query.toLowerCase());
    }).toList();

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.data_object), text: 'PC Journals'),
              Tab(icon: Icon(Icons.folder_copy_outlined), text: 'App Library'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _DesktopScroll(
                  children: [
                    _SectionTitle(
                      title: 'PC research sessions',
                      subtitle:
                          '.waj is authoritative; CSV is generated only on demand.',
                      trailing: FilledButton.tonalIcon(
                        onPressed: state.connected
                            ? ref
                                  .read(desktopAcquisitionProvider.notifier)
                                  .loadSessions
                            : null,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reload'),
                      ),
                    ),
                    TextField(
                      onChanged: (value) => setState(() => _query = value),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        labelText: 'Search session, athlete, topic or quality',
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    if (filtered.isEmpty)
                      const _EmptyDesktopState(
                        icon: Icons.folder_off_outlined,
                        title: 'No PC journals found',
                        message: 'Finalized recordings will appear here.',
                      )
                    else
                      for (final session in filtered)
                        _PcSessionCard(session: session),
                    _RecoveryPanel(state: state),
                  ],
                ),
                const BrowsePage(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PcSessionCard extends ConsumerWidget {
  const _PcSessionCard({required this.session});
  final Map<String, dynamic> session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quality = '${session['quality'] ?? 'UNKNOWN'}';
    final counts = _map(session['sample_counts']);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _QualityIcon(quality: quality),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${session['topic']?.toString().isNotEmpty == true ? session['topic'] : 'Untitled session'} · Trial ${session['trial_number'] ?? '—'}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${session['athlete']?.toString().isNotEmpty == true ? session['athlete'] : 'Unknown athlete'}',
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    children: [
                      Chip(label: Text(quality)),
                      Chip(
                        label: Text('${session['sample_rate_hz'] ?? '—'} Hz'),
                      ),
                      Chip(label: Text('L ${counts['L'] ?? 0} samples')),
                      Chip(label: Text('R ${counts['R'] ?? 0} samples')),
                      if (session['duration_s'] != null)
                        Chip(
                          label: Text(
                            '${(session['duration_s'] as num).toStringAsFixed(1)} s',
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  SelectableText(
                    '${session['session_id']}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                try {
                  final path = await ref
                      .read(desktopAcquisitionProvider.notifier)
                      .exportSession('${session['session_id']}');
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('CSV exported: $path')),
                    );
                  }
                } on Object catch (error) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Export failed: $error')),
                    );
                  }
                }
              },
              icon: const Icon(Icons.file_download_outlined),
              label: const Text('CSV'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecoveryPanel extends ConsumerWidget {
  const _RecoveryPanel({required this.state});
  final DesktopAcquisitionState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final raw = state.status['incomplete_sessions'];
    final files = raw is List
        ? raw.map((value) => '$value').toList()
        : const <String>[];
    if (files.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Crash recovery',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'These .open journals contain checksum-valid committed records and were not finalized.',
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final file in files)
              ListTile(
                dense: true,
                leading: const Icon(Icons.restore_page),
                title: Text(file),
                trailing: FilledButton.tonal(
                  onPressed: () async {
                    final path = await ref
                        .read(desktopAcquisitionProvider.notifier)
                        .recover(file);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Recovered: $path')),
                      );
                    }
                  },
                  child: const Text('Recover'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DesktopDiagnosticsPage extends ConsumerWidget {
  const _DesktopDiagnosticsPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(desktopAcquisitionProvider);
    final boards = _boards(state.status);
    return _DesktopScroll(
      children: [
        _SectionTitle(
          title: 'Acquisition diagnostics',
          subtitle:
              'Use data-path counters to judge link quality; RSSI is only one signal.',
          trailing: Wrap(
            spacing: AppSpacing.sm,
            children: [
              OutlinedButton.icon(
                onPressed: state.connected
                    ? ref
                          .read(desktopAcquisitionProvider.notifier)
                          .refreshStatus
                    : null,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
              FilledButton.icon(
                onPressed: state.connected
                    ? () async {
                        final path = await ref
                            .read(desktopAcquisitionProvider.notifier)
                            .exportDiagnosticReport();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Diagnostic report: $path')),
                          );
                        }
                      }
                    : null,
                icon: const Icon(Icons.download),
                label: const Text('Export report'),
              ),
            ],
          ),
        ),
        for (final side in const ['L', 'R']) ...[
          _DiagnosticBoard(side: side, board: boards[side] ?? const {}),
          const SizedBox(height: AppSpacing.md),
        ],
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Disk writer / session',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                _KeyValue('Journal root', state.status['journal_root']),
                _KeyValue('Active session', state.status['session_id']),
                _KeyValue('Recording', state.status['recording']),
                _KeyValue(
                  'Journal queue',
                  _map(state.status['journal'])['queue_high_water'],
                ),
                _KeyValue(
                  'Journal overflow',
                  _map(state.status['journal'])['queue_overflow_faults'],
                ),
                _KeyValue(
                  'Samples written',
                  _map(state.status['journal'])['samples_written'],
                ),
                _KeyValue(
                  'Max write latency',
                  _formatNs(
                    _map(state.status['journal'])['max_write_latency_ns'],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (state.error != null) ...[
          const SizedBox(height: AppSpacing.md),
          _ErrorBanner(message: state.error!),
        ],
      ],
    );
  }
}

class _DiagnosticBoard extends StatelessWidget {
  const _DiagnosticBoard({required this.side, required this.board});
  final String side;
  final Map<String, dynamic> board;

  @override
  Widget build(BuildContext context) {
    final info = _map(board['info']);
    final health = _map(board['health']);
    final clock = _map(board['clock']);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(child: Text(side)),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'Wheel $side',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                Chip(
                  label: Text(
                    board['connected'] == true ? 'CONNECTED' : 'OFFLINE',
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xl,
              runSpacing: AppSpacing.xs,
              children: [
                SizedBox(
                  width: 320,
                  child: Column(
                    children: [
                      _KeyValue(
                        'RSSI',
                        info['rssi'] == null ? null : '${info['rssi']} dBm',
                      ),
                      _KeyValue('MTU', board['mtu']),
                      const _KeyValue(
                        'Connection interval',
                        'Unavailable from current Bleak API',
                      ),
                      _KeyValue('Notifications', board['notifications']),
                      _KeyValue(
                        'Notifications/s',
                        _hz(board['notifications_hz']),
                      ),
                      _KeyValue('Samples', board['samples']),
                      _KeyValue('Samples/s', _hz(board['samples_hz'])),
                    ],
                  ),
                ),
                SizedBox(
                  width: 320,
                  child: Column(
                    children: [
                      _KeyValue('Sequence gaps', board['sequence_gaps']),
                      _KeyValue('Duplicates', board['duplicates']),
                      _KeyValue('Out of order', board['out_of_order']),
                      _KeyValue(
                        'Malformed packets',
                        board['malformed_packets'],
                      ),
                      _KeyValue('Callback queue depth', board['queue_depth']),
                      _KeyValue('Queue high-water', board['queue_high_water']),
                      _KeyValue(
                        'Queue overflow faults',
                        board['queue_overflow_faults'],
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 320,
                  child: Column(
                    children: [
                      _KeyValue('Firmware produced', health['produced']),
                      _KeyValue('Firmware notified', health['notified']),
                      _KeyValue('Firmware queue drops', health['queue_drops']),
                      _KeyValue(
                        'BLE transport failures',
                        health['transport_failures'],
                      ),
                      _KeyValue('Firmware queue depth', health['queue_depth']),
                      _KeyValue('FIFO faults', health['fifo_faults']),
                      _KeyValue(
                        'FIFO samples lost',
                        health['fifo_dropped_samples'],
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 320,
                  child: Column(
                    children: [
                      _KeyValue('Best RTT', _formatNs(clock['best_rtt_ns'])),
                      _KeyValue(
                        'Median RTT',
                        _formatNs(clock['median_rtt_ns']),
                      ),
                      _KeyValue(
                        'Clock intercept',
                        _formatNs(clock['intercept_ns']),
                      ),
                      _KeyValue(
                        'Drift',
                        clock['drift_ppm'] == null
                            ? null
                            : '${(clock['drift_ppm'] as num).toStringAsFixed(2)} ppm',
                      ),
                      _KeyValue(
                        'Residual RMS',
                        _formatNs(clock['residual_rms_ns']),
                      ),
                      _KeyValue(
                        'Sync observations',
                        clock['observation_count'],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (board['fatal_fault'] != null) ...[
              const SizedBox(height: AppSpacing.sm),
              _ErrorBanner(message: '${board['fatal_fault']}'),
            ],
          ],
        ),
      ),
    );
  }
}

class _BoardSummaryCard extends StatelessWidget {
  const _BoardSummaryCard({required this.side, required this.board});
  final String side;
  final Map<String, dynamic> board;

  @override
  Widget build(BuildContext context) {
    final info = _map(board['info']);
    final connected = board['connected'] == true;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(child: Text(side)),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    connected
                        ? '${info['name'] ?? 'Wheel $side'}'
                        : 'Wheel $side offline',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Icon(connected ? Icons.check_circle : Icons.cancel_outlined),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            _KeyValue(
              'RSSI',
              info['rssi'] == null ? null : '${info['rssi']} dBm',
            ),
            _KeyValue('MTU', board['mtu']),
            _KeyValue(
              'Configured',
              info['sample_rate_hz'] == null
                  ? null
                  : '${info['sample_rate_hz']} Hz',
            ),
            _KeyValue('Received', _hz(board['samples_hz'])),
            _KeyValue('Samples', board['samples']),
            _KeyValue('Seq gaps', board['sequence_gaps']),
            _KeyValue(
              'Host queue',
              '${board['queue_depth'] ?? 0} · high ${board['queue_high_water'] ?? 0}',
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.detail,
    required this.icon,
  });
  final String title;
  final String value;
  final String detail;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 310,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              CircleAvatar(child: Icon(icon)),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.labelLarge),
                    Text(
                      value,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    required this.subtitle,
    this.trailing,
  });
  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.md),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class _DesktopScroll extends StatelessWidget {
  const _DesktopScroll({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: children,
    );
  }
}

class _KeyValue extends StatelessWidget {
  const _KeyValue(this.label, this.value);
  final String label;
  final Object? value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 145,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: Text(
              value == null ? '—' : '$value',
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallMetric extends StatelessWidget {
  const _SmallMetric(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          Text(value, style: Theme.of(context).textTheme.titleSmall),
        ],
      ),
    );
  }
}

class _ValueTile extends StatelessWidget {
  const _ValueTile(this.label, this.value, this.unit);
  final String label;
  final double value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 132,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          Text(
            '${value.toStringAsFixed(3)} $unit',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}

class _QualityIcon extends StatelessWidget {
  const _QualityIcon({required this.quality});
  final String quality;

  @override
  Widget build(BuildContext context) {
    final normalized = quality.toUpperCase();
    final icon = switch (normalized) {
      'GOOD' => Icons.verified,
      'WARNING' => Icons.warning_amber,
      'DEGRADED' => Icons.report_problem,
      'INVALID' => Icons.dangerous,
      _ => Icons.help_outline,
    };
    return CircleAvatar(child: Icon(icon));
  }
}

class _EmptyDesktopState extends StatelessWidget {
  const _EmptyDesktopState({
    required this.icon,
    required this.title,
    required this.message,
  });
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).disabledColor),
            const SizedBox(height: AppSpacing.sm),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Map<String, Map<String, dynamic>> _boards(Map<String, dynamic> status) {
  final raw = status['boards'];
  if (raw is! Map) return const {};
  return {
    for (final entry in raw.entries)
      '${entry.key}': entry.value is Map
          ? Map<String, dynamic>.from(entry.value as Map)
          : <String, dynamic>{},
  };
}

Map<String, dynamic> _map(Object? value) {
  return value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
}

String _hz(Object? value) {
  if (value is num) return '${value.toStringAsFixed(1)} Hz';
  return '—';
}

String _formatNs(Object? value) {
  if (value is! num) return '—';
  final ns = value.toDouble();
  if (ns.abs() >= 1e6) return '${(ns / 1e6).toStringAsFixed(3)} ms';
  if (ns.abs() >= 1e3) return '${(ns / 1e3).toStringAsFixed(1)} µs';
  return '${ns.toStringAsFixed(0)} ns';
}

String _formatDuration(Duration value) {
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  final hours = value.inHours;
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}
