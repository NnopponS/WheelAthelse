import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/ble/ble_repository.dart';
import 'package:wheelathlete/ble/device_info.dart';
import 'package:wheelathlete/ble/wheel_id.dart';
import 'package:wheelathlete/state/ble_providers.dart';
import 'package:wheelathlete/state/imu_providers.dart';
import 'package:wheelathlete/theme/theme.dart';

/// Builds a 20-byte IMU sample for tests.
Uint8List buildSample({
  required int seq,
  required int tDeviceUs,
  int ax = 0,
  int ay = 0,
  int az = 0,
  int gx = 0,
  int gy = 0,
  int gz = 0,
}) {
  final b = ByteData(20)
    ..setUint32(0, seq, Endian.little)
    ..setUint32(4, tDeviceUs, Endian.little)
    ..setInt16(8, ax, Endian.little)
    ..setInt16(10, ay, Endian.little)
    ..setInt16(12, az, Endian.little)
    ..setInt16(14, gx, Endian.little)
    ..setInt16(16, gy, Endian.little)
    ..setInt16(18, gz, Endian.little);
  return b.buffer.asUint8List();
}

Uint8List buildBatch(List<Uint8List> samples) {
  final body = BytesBuilder();
  for (final s in samples) {
    body.add(s);
  }
  return (BytesBuilder()
        ..addByte(samples.length)
        ..add(body.toBytes()))
      .toBytes();
}

const _leftInfo = DeviceInfo(
  wheelId: WheelId.left,
  fwMajor: 1,
  fwMinor: 0,
  fwPatch: 0,
  accelRange: 0,
  gyroRange: 3,
  accelScale: 1 / 16384,
  gyroScale: 1 / 16.4,
);

void main() {
  late FakeBleRepository ble;
  late ProviderContainer container;

  setUp(() {
    ble = FakeBleRepository(
      devices: [
        const FakeDevice(id: 'L1', name: 'WheelAthlete-L', rssi: -42),
      ],
      infoFor: const {'L1': _leftInfo},
    );
    container = ProviderContainer(
      overrides: [bleRepositoryProvider.overrideWith((ref) => ble)],
    );
    addTearDown(container.dispose);
  });

  ImuStreamState state() => container.read(imuStreamProvider);

  test('initial state: both sides idle, not streaming, no samples', () {
    final s = state();
    expect(s.bySide[WheelSide.left]!.streaming, isFalse);
    expect(s.bySide[WheelSide.left]!.latest, isNull);
    expect(s.bySide[WheelSide.left]!.sampleCount, 0);
    expect(s.bySide[WheelSide.left]!.dropCount, 0);
    expect(s.bySide[WheelSide.right]!.streaming, isFalse);
  });

  test('start sets streaming=true for the side', () async {
    // Connect first so the notifier can resolve the device id + info.
    await container.read(connectionManagerProvider.notifier).connect('L1');
    final notifier = container.read(imuStreamProvider.notifier);
    await notifier.start(WheelSide.left);

    expect(state().bySide[WheelSide.left]!.streaming, isTrue);
  });

  test('start without a connected device sets error, does not stream', () async {
    final notifier = container.read(imuStreamProvider.notifier);
    await notifier.start(WheelSide.left);

    final s = state().bySide[WheelSide.left]!;
    expect(s.streaming, isFalse);
    expect(s.error, isNotNull);
  });

  test('IMU notify updates latest reading + sample count', () async {
    await container.read(connectionManagerProvider.notifier).connect('L1');
    final notifier = container.read(imuStreamProvider.notifier);
    await notifier.start(WheelSide.left);

    // Emit a 2-sample batch: seq 0,1 with ax=16384 (→ 1.0 g).
    ble.imuController('L1')!.add(buildBatch([
      buildSample(seq: 0, tDeviceUs: 1000, ax: 16384),
      buildSample(seq: 1, tDeviceUs: 1100, ax: 16384),
    ]));

    final s = state().bySide[WheelSide.left]!;
    expect(s.streaming, isTrue);
    expect(s.sampleCount, 2);
    expect(s.latest, isNotNull);
    expect(s.latest!.seq, 1);
    expect(s.latest!.ax, closeTo(1.0, 1e-9));
    expect(s.dropCount, 0);
  });

  test('seq gap increments dropCount', () async {
    await container.read(connectionManagerProvider.notifier).connect('L1');
    final notifier = container.read(imuStreamProvider.notifier);
    await notifier.start(WheelSide.left);

    ble.imuController('L1')!.add(buildBatch([
      buildSample(seq: 0, tDeviceUs: 0),
    ]));
    // Next batch jumps from seq 0 → seq 5 (gap of 4).
    ble.imuController('L1')!.add(buildBatch([
      buildSample(seq: 5, tDeviceUs: 500),
    ]));

    final s = state().bySide[WheelSide.left]!;
    expect(s.sampleCount, 2);
    expect(s.dropCount, 4);
  });

  test('multiple batches accumulate sample count and gaps', () async {
    await container.read(connectionManagerProvider.notifier).connect('L1');
    final notifier = container.read(imuStreamProvider.notifier);
    await notifier.start(WheelSide.left);

    final ctrl = ble.imuController('L1')!;
    ctrl.add(buildBatch([buildSample(seq: 0, tDeviceUs: 0)]));
    ctrl.add(buildBatch([
      buildSample(seq: 1, tDeviceUs: 10),
      buildSample(seq: 2, tDeviceUs: 20),
    ]));
    ctrl.add(buildBatch([buildSample(seq: 10, tDeviceUs: 100)])); // gap 7

    final s = state().bySide[WheelSide.left]!;
    expect(s.sampleCount, 4);
    expect(s.dropCount, 7);
    expect(s.latest!.seq, 10);
  });

  test('stop sets streaming=false and keeps last reading', () async {
    await container.read(connectionManagerProvider.notifier).connect('L1');
    final notifier = container.read(imuStreamProvider.notifier);
    await notifier.start(WheelSide.left);

    ble.imuController('L1')!.add(buildBatch([
      buildSample(seq: 0, tDeviceUs: 0, ax: 16384),
    ]));
    expect(state().bySide[WheelSide.left]!.sampleCount, 1);

    await notifier.stop(WheelSide.left);
    final s = state().bySide[WheelSide.left]!;
    expect(s.streaming, isFalse);
    // Latest reading is retained so the UI can show the last value after stop.
    expect(s.latest, isNotNull);
    expect(s.latest!.seq, 0);
  });

  test('start twice replaces the previous subscription (no leak)', () async {
    await container.read(connectionManagerProvider.notifier).connect('L1');
    final notifier = container.read(imuStreamProvider.notifier);
    await notifier.start(WheelSide.left);
    final firstCtrl = ble.imuController('L1')!;

    // Restart — should cancel the old sub and subscribe anew.
    await notifier.start(WheelSide.left);
    final secondCtrl = ble.imuController('L1')!;
    expect(identical(firstCtrl, secondCtrl), isTrue);

    secondCtrl.add(buildBatch([buildSample(seq: 0, tDeviceUs: 0)]));
    expect(state().bySide[WheelSide.left]!.sampleCount, 1);
  });

  test('stream error sets error and stops streaming', () async {
    await container.read(connectionManagerProvider.notifier).connect('L1');
    final notifier = container.read(imuStreamProvider.notifier);
    await notifier.start(WheelSide.left);

    ble.imuController('L1')!.addError(StateError('BLE link lost'));

    final s = state().bySide[WheelSide.left]!;
    expect(s.streaming, isFalse);
    expect(s.error, isNotNull);
  });

  test('malformed batch sets error and stops streaming', () async {
    await container.read(connectionManagerProvider.notifier).connect('L1');
    final notifier = container.read(imuStreamProvider.notifier);
    await notifier.start(WheelSide.left);

    // count=3 but only 1 sample — parseBatch throws ArgumentError.
    ble.imuController('L1')!.add(Uint8List.fromList([
      3,
      ...buildSample(seq: 0, tDeviceUs: 0),
    ]));

    final s = state().bySide[WheelSide.left]!;
    expect(s.streaming, isFalse);
    expect(s.error, isNotNull);
  });

  test('stop on a non-streaming side is a no-op', () async {
    final notifier = container.read(imuStreamProvider.notifier);
    await notifier.stop(WheelSide.right);
    expect(state().bySide[WheelSide.right]!.streaming, isFalse);
  });

  test('dispose cancels all IMU subscriptions', () async {
    await container.read(connectionManagerProvider.notifier).connect('L1');
    final notifier = container.read(imuStreamProvider.notifier);
    await notifier.start(WheelSide.left);
    final ctrl = ble.imuController('L1')!;

    container.dispose();
    // Adding to the controller after dispose must not throw into nowhere.
    ctrl.add(buildBatch([buildSample(seq: 0, tDeviceUs: 0)]));
    expect(ctrl.hasListener, isFalse);
  });

  test('IMU notify accumulates readings into the rolling chart buffer',
      () async {
    await container.read(connectionManagerProvider.notifier).connect('L1');
    final notifier = container.read(imuStreamProvider.notifier);
    await notifier.start(WheelSide.left);

    // First batch: 2 samples.
    ble.imuController('L1')!.add(buildBatch([
      buildSample(seq: 0, tDeviceUs: 0, ax: 16384),
      buildSample(seq: 1, tDeviceUs: 10000, ax: 16384),
    ]));
    var s = state().bySide[WheelSide.left]!;
    expect(s.recent.length, 2);
    expect(s.recent.first.seq, 0);
    expect(s.recent.last.seq, 1);

    // Second batch: 1 more sample → buffer grows to 3.
    ble.imuController('L1')!.add(buildBatch([
      buildSample(seq: 2, tDeviceUs: 20000, ax: 16384),
    ]));
    s = state().bySide[WheelSide.left]!;
    expect(s.recent.length, 3);
    expect(s.recent.last.seq, 2);
  });

  test('chart buffer is capped at WheelImuState.chartBufferCap', () async {
    await container.read(connectionManagerProvider.notifier).connect('L1');
    final notifier = container.read(imuStreamProvider.notifier);
    await notifier.start(WheelSide.left);
    final ctrl = ble.imuController('L1')!;

    // Feed enough batches to exceed the cap (300). Each batch has 1 sample.
    for (var i = 0; i < WheelImuState.chartBufferCap + 50; i++) {
      ctrl.add(buildBatch([buildSample(seq: i, tDeviceUs: i * 1000)]));
    }
    final s = state().bySide[WheelSide.left]!;
    expect(s.recent.length, WheelImuState.chartBufferCap);
    // Oldest entries dropped; the buffer holds the most recent readings.
    expect(s.recent.last.seq, WheelImuState.chartBufferCap + 50 - 1);
  });

  test('start resets the chart buffer', () async {
    await container.read(connectionManagerProvider.notifier).connect('L1');
    final notifier = container.read(imuStreamProvider.notifier);
    await notifier.start(WheelSide.left);
    ble.imuController('L1')!.add(buildBatch([
      buildSample(seq: 0, tDeviceUs: 0, ax: 16384),
    ]));
    expect(state().bySide[WheelSide.left]!.recent.length, 1);

    // Restart — buffer should be cleared.
    await notifier.start(WheelSide.left);
    expect(state().bySide[WheelSide.left]!.recent, isEmpty);
  });
}
