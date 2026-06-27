import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:wheelsense/theme/theme.dart';
import 'package:wheelsense/widgets/widgets.dart';

/// Living style guide: renders every design-system token and reusable
/// component with mock data. Used during development to review the UI and as a
/// reference for the screens built in subtasks #5/#6/#8/#9.
class ShowcasePage extends StatefulWidget {
  const ShowcasePage({super.key, required this.controller});

  final ThemeModeController controller;

  @override
  State<ShowcasePage> createState() => _ShowcasePageState();
}

class _ShowcasePageState extends State<ShowcasePage> {
  Timer? _timer;
  double _t = 0;
  int _markers = 3;
  bool _recording = false;

  @override
  void initState() {
    super.initState();
    // Animate the mock IMU values so live readouts look alive in the preview.
    _timer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      if (!mounted) return;
      setState(() => _t += 0.12);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  double _wave(double phase, double amp) => math.sin(_t + phase) * amp;

  PopupMenuItem<ThemeMode> _modeItem(
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
          if (mode == current)
            const Icon(Icons.check_rounded, size: 18),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WheelSense UI'),
        actions: [
          PopupMenuButton<ThemeMode>(
            tooltip: 'Theme mode',
            icon: Icon(
              widget.controller.isDark(context)
                  ? Icons.light_mode_rounded
                  : Icons.dark_mode_rounded,
            ),
            onSelected: widget.controller.set,
            itemBuilder: (context) {
              final current = widget.controller.value;
              return [
                _modeItem(ThemeMode.system, 'System', current,
                    Icons.brightness_auto_rounded),
                _modeItem(ThemeMode.light, 'Light', current,
                    Icons.light_mode_rounded),
                _modeItem(ThemeMode.dark, 'Dark', current,
                    Icons.dark_mode_rounded),
              ];
            },
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSizing.maxContentWidth),
          child: ListView(
            padding: AppSpacing.pagePadding,
            children: [
              _Section(
                title: 'Color roles',
                child: _ColorRolesPreview(),
              ),
              _Section(
                title: 'Typography',
                child: _TypographyPreview(),
              ),
              const _Section(
                title: 'Status badges',
                child: Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    StatusBadge(label: 'Connected', tone: BadgeTone.success, icon: Icons.check_circle_rounded),
                    StatusBadge(label: 'Connecting', tone: BadgeTone.warning, icon: Icons.sync_rounded),
                    StatusBadge(label: 'Disconnected', tone: BadgeTone.neutral, icon: Icons.cloud_off_rounded),
                    StatusBadge(label: 'Error', tone: BadgeTone.danger, icon: Icons.error_rounded),
                    StatusBadge(label: 'L', tone: BadgeTone.left),
                    StatusBadge(label: 'R', tone: BadgeTone.right),
                    StatusBadge(label: 'Recording', tone: BadgeTone.info, icon: Icons.fiber_manual_record_rounded),
                  ],
                ),
              ),
              _Section(
                title: 'Connection cards',
                child: Column(
                  children: [
                    ConnectionCard(
                      side: WheelSide.left,
                      status: ConnectionStatus.connected,
                      deviceName: 'WheelSense-L',
                      batteryPercent: 82,
                      rssi: -54,
                      onTap: () {},
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    ConnectionCard(
                      side: WheelSide.right,
                      status: ConnectionStatus.connecting,
                      deviceName: 'WheelSense-R',
                      batteryPercent: 12,
                      rssi: -78,
                      onTap: () {},
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    const ConnectionCard(
                      side: WheelSide.right,
                      status: ConnectionStatus.disconnected,
                    ),
                  ],
                ),
              ),
              _Section(
                title: 'Live metric tiles',
                child: GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: AppSpacing.xs,
                  crossAxisSpacing: AppSpacing.xs,
                  childAspectRatio: 1.6,
                  children: [
                    LiveMetricTile(label: 'ax', value: _wave(0, 1.2), unit: 'g', side: WheelSide.left),
                    LiveMetricTile(label: 'ay', value: _wave(1, 1.2), unit: 'g', side: WheelSide.left),
                    LiveMetricTile(label: 'az', value: 1 + _wave(2, 0.3), unit: 'g', side: WheelSide.left),
                    LiveMetricTile(label: 'gx', value: _wave(0, 240), unit: '°/s', side: WheelSide.right, fractionDigits: 1),
                    LiveMetricTile(label: 'gy', value: _wave(1, 240), unit: '°/s', side: WheelSide.right, fractionDigits: 1),
                    LiveMetricTile(label: 'gz', value: _wave(2, 240), unit: '°/s', side: WheelSide.right, fractionDigits: 1),
                  ],
                ),
              ),
              _Section(
                title: 'Primary actions',
                child: Column(
                  children: [
                    PrimaryActionButton(
                      label: _recording ? 'Stop recording' : 'Start recording',
                      icon: _recording ? Icons.stop_rounded : Icons.play_arrow_rounded,
                      intent: _recording ? ActionIntent.stop : ActionIntent.start,
                      onPressed: () => setState(() => _recording = !_recording),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    const PrimaryActionButton(
                      label: 'Syncing clocks…',
                      icon: Icons.sync_rounded,
                      busy: true,
                      onPressed: null,
                    ),
                  ],
                ),
              ),
              _Section(
                title: 'Mark event',
                child: Center(
                  child: MarkEventButton(
                    markerCount: _markers,
                    enabled: _recording,
                    onPressed: () => setState(() => _markers++),
                  ),
                ),
              ),
              _Section(
                title: 'Session list',
                child: Column(
                  children: [
                    SessionListItem(
                      title: 'session_a1f3',
                      subtitle: 'trial_03 · 2026-06-28 14:21',
                      duration: const Duration(minutes: 2, seconds: 14),
                      sampleCount: 12840,
                      markerCount: 4,
                      syncQuality: '±0.8 ms',
                      onTap: () {},
                      onShare: () {},
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    SessionListItem(
                      title: 'session_b22c',
                      subtitle: 'trial_02 · 2026-06-28 14:05',
                      duration: const Duration(seconds: 48),
                      sampleCount: 4200,
                      onTap: () {},
                      onShare: () {},
                    ),
                  ],
                ),
              ),
              _Section(
                title: 'Empty state',
                child: _Framed(child: EmptyState(
                  title: 'No sessions yet',
                  message: 'Connect both wheels and start recording to capture your first trial.',
                  icon: Icons.sensors_rounded,
                  actionLabel: 'Scan for devices',
                  onAction: () {},
                )),
              ),
              const _Section(
                title: 'Loading state',
                child: _Framed(
                  child: LoadingState(message: 'Scanning for WheelSense devices…'),
                ),
              ),
              _Section(
                title: 'Error state',
                child: _Framed(child: ErrorState(
                  title: 'Lost connection',
                  message: 'The right wheel dropped off. Move closer and retry.',
                  onRetry: () {},
                )),
              ),
              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }
}

/// A titled block in the style guide.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: AppTypography.eyebrow(theme.colorScheme.primary),
          ),
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    );
  }
}

/// Bordered container giving full-screen states a bounded preview box.
class _Framed extends StatelessWidget {
  const _Framed({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 220),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: AppRadius.brLg,
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: child,
      ),
    );
  }
}

class _ColorRolesPreview extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final wc = context.wheelColors;
    final entries = <(String, ColorRole)>[
      ('Left', wc.left),
      ('Right', wc.right),
      ('Success', wc.success),
      ('Warning', wc.warning),
      ('Danger', wc.danger),
    ];
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        for (final (name, role) in entries)
          Container(
            width: 92,
            padding: const EdgeInsets.all(AppSpacing.xs),
            decoration: BoxDecoration(
              color: role.container,
              borderRadius: AppRadius.brMd,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 28,
                  decoration: BoxDecoration(
                    color: role.solid,
                    borderRadius: AppRadius.brSm,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  name,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: role.onContainer,
                      ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _TypographyPreview extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Display', style: t.displayMedium),
        Text('Headline', style: t.headlineMedium),
        Text('Title large', style: t.titleLarge),
        Text('Body large — readable under sunlight.', style: t.bodyLarge),
        Text('Body small / muted caption', style: t.bodySmall),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '+9.81 m/s²  (tabular mono)',
          style: AppTypography.metric(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 20,
          ),
        ),
      ],
    );
  }
}
