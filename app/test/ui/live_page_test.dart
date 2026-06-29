import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/ble/ble_repository.dart';
import 'package:wheelathlete/ble/device_info.dart';
import 'package:wheelathlete/ble/wheel_id.dart';
import 'package:wheelathlete/state/ble_providers.dart';
import 'package:wheelathlete/theme/theme.dart';
import 'package:wheelathlete/ui/live_page.dart';

import '../helpers/pump.dart';

Uint8List _sample({
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

Uint8List _batch(List<Uint8List> samples) {
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

const _rightInfo = DeviceInfo(
  wheelId: WheelId.right,
  fwMajor: 1,
  fwMinor: 0,
  fwPatch: 0,
  accelRange: 0,
  gyroRange: 3,
  accelScale: 1 / 16384,
  gyroScale: 1 / 16.4,
);

void main() {
  setUpAll(disableGoogleFontsFetching);

  late FakeBleRepository ble;
  late ProviderContainer container;

  Future<void> pumpLivePage(WidgetTester tester) async {
    container = ProviderContainer(
      overrides: [bleRepositoryProvider.overrideWith((ref) => ble)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          home: const LivePage(),
        ),
      ),
    );
  }

  setUp(() {
    ble = FakeBleRepository(
      devices: [
        const FakeDevice(id: 'L1', name: 'WheelAthlete-L', rssi: -42),
        const FakeDevice(id: 'R1', name: 'WheelAthlete-R', rssi: -55),
      ],
      infoFor: const {'L1': _leftInfo, 'R1': _rightInfo},
    );
  });

  testWidgets('shows both wheel panels with "not connected" when idle',
      (tester) async {
    await pumpLivePage(tester);

    expect(find.text('Live IMU'), findsOneWidget);
    // Both sides show a not-connected hint.
    expect(find.text('Not connected'), findsNWidgets(2));
  });

  testWidgets('shows Start button disabled when neither wheel is connected',
      (tester) async {
    await pumpLivePage(tester);

    final startBtn = find.byKey(LivePage.startButtonKey);
    expect(startBtn, findsOneWidget);
    expect(
      tester.widget<FloatingActionButton>(startBtn).onPressed,
      isNull,
    );
  });

  testWidgets('Start button enables when at least one wheel is connected',
      (tester) async {
    await pumpLivePage(tester);
    await container.read(connectionManagerProvider.notifier).connect('L1');
    await tester.pumpAndSettle();

    final startBtn = find.byKey(LivePage.startButtonKey);
    expect(tester.widget<FloatingActionButton>(startBtn).onPressed, isNotNull);
  });

  testWidgets('tapping Start begins streaming and shows live values for L',
      (tester) async {
    await pumpLivePage(tester);
    await container.read(connectionManagerProvider.notifier).connect('L1');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(LivePage.startButtonKey));
    await tester.pumpAndSettle();

    // Emit a batch: seq 0, ax=16384 (→ 1.0 g), gx=164 (→ 10 dps).
    ble.imuController('L1')!.add(_batch([
      _sample(seq: 0, tDeviceUs: 1000, ax: 16384, gx: 164),
    ]));
    await tester.pumpAndSettle();

    // The Left panel should show the ax value (+1.00) and gx value (+10.00).
    expect(find.text('+1.00'), findsWidgets);
    expect(find.text('+10.00'), findsWidgets);
    // Sample count should be visible.
    expect(find.textContaining('1 sample'), findsWidgets);
  });

  testWidgets('tapping Stop stops streaming and keeps last value visible',
      (tester) async {
    await pumpLivePage(tester);
    await container.read(connectionManagerProvider.notifier).connect('L1');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(LivePage.startButtonKey));
    await tester.pumpAndSettle();
    ble.imuController('L1')!.add(_batch([
      _sample(seq: 0, tDeviceUs: 0, ax: 16384),
    ]));
    await tester.pumpAndSettle();
    expect(find.text('+1.00'), findsWidgets);

    // Stop button is now the same FAB (toggles label).
    await tester.tap(find.byKey(LivePage.startButtonKey));
    await tester.pumpAndSettle();

    // Last value is still shown after stop.
    expect(find.text('+1.00'), findsWidgets);
  });

  testWidgets('shows drop count badge when seq gap is detected', (tester) async {
    await pumpLivePage(tester);
    await container.read(connectionManagerProvider.notifier).connect('L1');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(LivePage.startButtonKey));
    await tester.pumpAndSettle();

    ble.imuController('L1')!.add(_batch([_sample(seq: 0, tDeviceUs: 0)]));
    await tester.pumpAndSettle();
    ble.imuController('L1')!.add(_batch([_sample(seq: 5, tDeviceUs: 50)]));
    await tester.pumpAndSettle();

    // Gap of 4 should be surfaced somewhere in the Left panel.
    expect(find.textContaining('4 dropped'), findsWidgets);
  });

  testWidgets('shows error message when stream errors', (tester) async {
    await pumpLivePage(tester);
    await container.read(connectionManagerProvider.notifier).connect('L1');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(LivePage.startButtonKey));
    await tester.pumpAndSettle();

    ble.imuController('L1')!.addError(StateError('link lost'));
    await tester.pumpAndSettle();

    expect(find.textContaining('error'), findsWidgets);
  });

  testWidgets('both wheels stream independently', (tester) async {
    await pumpLivePage(tester);
    await container.read(connectionManagerProvider.notifier).connect('L1');
    await container.read(connectionManagerProvider.notifier).connect('R1');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(LivePage.startButtonKey));
    await tester.pumpAndSettle();

    ble.imuController('L1')!.add(_batch([
      _sample(seq: 0, tDeviceUs: 0, ax: 16384),
    ]));
    await tester.pump();
    ble.imuController('R1')!.add(_batch([
      _sample(seq: 0, tDeviceUs: 0, az: 16384),
    ]));
    await tester.pumpAndSettle();

    // Both ax (L) and az (R) should show +1.00 — exactly 2 occurrences.
    expect(find.text('+1.00'), findsNWidgets(2));
  });
}
