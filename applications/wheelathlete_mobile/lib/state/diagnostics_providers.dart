import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wheelathlete/state/ble_providers.dart';
import 'package:wheelathlete/state/dashboard_providers.dart';
import 'package:wheelathlete/state/imu_providers.dart';
import 'package:wheelathlete/state/recording_providers.dart';
import 'package:wheelathlete/state/sync_providers.dart';
import 'package:wheelathlete/theme/theme.dart';
import 'package:wheelathlete/widgets/connection_card.dart';

@immutable
class DiagnosticRow {
  const DiagnosticRow({
    required this.metric,
    required this.left,
    required this.right,
    required this.center,
  });

  final String metric;
  final String left;
  final String right;
  final String center;
}

final diagnosticsMetricsProvider = Provider<List<DiagnosticRow>>((ref) {
  final conn = ref.watch(connectionManagerProvider);
  final imu = ref.watch(imuStreamProvider);
  final recording = ref.watch(recordingProvider);
  final settings = ref.watch(dashboardSettingsProvider);
  final syncState = ref.watch(syncEngineProvider);

  String accelLabel(int range) => switch (range) {
    0 => '±2g',
    1 => '±4g',
    2 => '±8g',
    3 => '±16g',
    _ => '—',
  };

  String gyroLabel(int range) => switch (range) {
    0 => '±250°/s',
    1 => '±500°/s',
    2 => '±1000°/s',
    3 => '±2000°/s',
    _ => '—',
  };

  String val(WheelSide side, String Function(WheelConnection c, WheelImuState i, RecordingWheelHealth? h) fn) {
    final c = conn.bySide[side];
    final i = imu.bySide[side];
    final h = recording.healthBySide[side];
    if (c == null || i == null) return '—';
    return fn(c, i, h);
  }

  return [
    DiagnosticRow(
      metric: 'Link status',
      left: val(WheelSide.left, (c, _, _) => c.status == ConnectionStatus.connected ? 'Connected' : 'Offline'),
      right: val(WheelSide.right, (c, _, _) => c.status == ConnectionStatus.connected ? 'Connected' : 'Offline'),
      center: val(WheelSide.center, (c, _, _) => c.status == ConnectionStatus.connected ? 'Connected' : 'Offline'),
    ),
    DiagnosticRow(
      metric: 'RSSI',
      left: val(WheelSide.left, (c, _, _) => c.rssi != null ? '${c.rssi} dBm' : '—'),
      right: val(WheelSide.right, (c, _, _) => c.rssi != null ? '${c.rssi} dBm' : '—'),
      center: val(WheelSide.center, (c, _, _) => c.rssi != null ? '${c.rssi} dBm' : '—'),
    ),
    DiagnosticRow(
      metric: 'Battery',
      left: val(WheelSide.left, (c, _, _) => c.batteryPercent != null ? '${c.batteryPercent}%' : '—'),
      right: val(WheelSide.right, (c, _, _) => c.batteryPercent != null ? '${c.batteryPercent}%' : '—'),
      center: val(WheelSide.center, (c, _, _) => c.batteryPercent != null ? '${c.batteryPercent}%' : '—'),
    ),
    DiagnosticRow(
      metric: 'Configured rate',
      left: '${settings.rateHz} Hz',
      right: '${settings.rateHz} Hz',
      center: '${settings.rateHz} Hz',
    ),
    DiagnosticRow(
      metric: 'Accel range',
      left: accelLabel(settings.accelRange),
      right: accelLabel(settings.accelRange),
      center: accelLabel(settings.accelRange),
    ),
    DiagnosticRow(
      metric: 'Gyro range',
      left: gyroLabel(settings.gyroRange),
      right: gyroLabel(settings.gyroRange),
      center: gyroLabel(settings.gyroRange),
    ),
    DiagnosticRow(
      metric: 'Effective rate',
      left: val(WheelSide.left, (_, _, h) => '${(h?.effectiveRateHz ?? 0).toStringAsFixed(1)} Hz'),
      right: val(WheelSide.right, (_, _, h) => '${(h?.effectiveRateHz ?? 0).toStringAsFixed(1)} Hz'),
      center: val(WheelSide.center, (_, _, h) => '${(h?.effectiveRateHz ?? 0).toStringAsFixed(1)} Hz'),
    ),
    DiagnosticRow(
      metric: 'Host samples',
      left: val(WheelSide.left, (_, i, h) => '${h?.receivedCount ?? i.sampleCount}'),
      right: val(WheelSide.right, (_, i, h) => '${h?.receivedCount ?? i.sampleCount}'),
      center: val(WheelSide.center, (_, i, h) => '${h?.receivedCount ?? i.sampleCount}'),
    ),
    DiagnosticRow(
      metric: 'Sequence gaps',
      left: val(WheelSide.left, (_, i, h) => '${i.dropCount + (h?.unrecoveredSamples ?? 0)}'),
      right: val(WheelSide.right, (_, i, h) => '${i.dropCount + (h?.unrecoveredSamples ?? 0)}'),
      center: val(WheelSide.center, (_, i, h) => '${i.dropCount + (h?.unrecoveredSamples ?? 0)}'),
    ),
    DiagnosticRow(
      metric: 'Queue drops',
      left: val(WheelSide.left, (_, _, h) => '${h?.queueDrops ?? 0}'),
      right: val(WheelSide.right, (_, _, h) => '${h?.queueDrops ?? 0}'),
      center: val(WheelSide.center, (_, _, h) => '${h?.queueDrops ?? 0}'),
    ),
    DiagnosticRow(
      metric: 'FIFO faults',
      left: val(WheelSide.left, (_, _, h) => '${h?.fifoFaults ?? 0}'),
      right: val(WheelSide.right, (_, _, h) => '${h?.fifoFaults ?? 0}'),
      center: val(WheelSide.center, (_, _, h) => '${h?.fifoFaults ?? 0}'),
    ),
    DiagnosticRow(
      metric: 'Device',
      left: val(WheelSide.left, (c, _, _) => (c.deviceName ?? '').isNotEmpty ? c.deviceName! : '—'),
      right: val(WheelSide.right, (c, _, _) => (c.deviceName ?? '').isNotEmpty ? c.deviceName! : '—'),
      center: val(WheelSide.center, (c, _, _) => (c.deviceName ?? '').isNotEmpty ? c.deviceName! : '—'),
    ),
    DiagnosticRow(
      metric: 'Best sync RTT',
      left: val(WheelSide.left, (_, _, _) => syncState.bySide[WheelSide.left]?.offset != null ? '${syncState.bySide[WheelSide.left]!.offset!.rttMs.toStringAsFixed(1)} ms' : '—'),
      right: val(WheelSide.right, (_, _, _) => syncState.bySide[WheelSide.right]?.offset != null ? '${syncState.bySide[WheelSide.right]!.offset!.rttMs.toStringAsFixed(1)} ms' : '—'),
      center: val(WheelSide.center, (_, _, _) => syncState.bySide[WheelSide.center]?.offset != null ? '${syncState.bySide[WheelSide.center]!.offset!.rttMs.toStringAsFixed(1)} ms' : '—'),
    ),
    DiagnosticRow(
      metric: 'Clock offset (µs)',
      left: val(WheelSide.left, (c, _, _) => '${syncState.bySide[WheelSide.left]?.offset?.offsetUs ?? '—'}'),
      right: val(WheelSide.right, (c, _, _) => '${syncState.bySide[WheelSide.right]?.offset?.offsetUs ?? '—'}'),
      center: val(WheelSide.center, (c, _, _) => '${syncState.bySide[WheelSide.center]?.offset?.offsetUs ?? '—'}'),
    ),
    DiagnosticRow(
      metric: 'Clock drift (ppm)',
      left: val(WheelSide.left, (c, _, _) => syncState.bySide[WheelSide.left]?.driftFit != null ? '${syncState.bySide[WheelSide.left]!.driftFit!.driftPpm.toStringAsFixed(1)} ppm' : '—'),
      right: val(WheelSide.right, (c, _, _) => syncState.bySide[WheelSide.right]?.driftFit != null ? '${syncState.bySide[WheelSide.right]!.driftFit!.driftPpm.toStringAsFixed(1)} ppm' : '—'),
      center: val(WheelSide.center, (c, _, _) => syncState.bySide[WheelSide.center]?.driftFit != null ? '${syncState.bySide[WheelSide.center]!.driftFit!.driftPpm.toStringAsFixed(1)} ppm' : '—'),
    ),
  ];
});

String generateDiagnosticsJson(WidgetRef ref) {
  final rows = ref.read(diagnosticsMetricsProvider);
  final map = <String, dynamic>{
    'exported_at': DateTime.now().toUtc().toIso8601String(),
    'app': 'WheelAthlete Mobile',
    'metrics': [
      for (final r in rows)
        {
          'metric': r.metric,
          'L': r.left,
          'R': r.right,
          'C': r.center,
        }
    ],
  };
  return const JsonEncoder.withIndent('  ').convert(map);
}
