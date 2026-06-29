import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/ble/ble_repository.dart';
import 'package:wheelathlete/ble/device_info.dart';
import 'package:wheelathlete/ble/wheel_id.dart';
import 'package:wheelathlete/state/ble_providers.dart';
import 'package:wheelathlete/theme/theme.dart';
import 'package:wheelathlete/ui/connect_page.dart';

import '../helpers/pump.dart';

void main() {
  setUpAll(disableGoogleFontsFetching);

  Future<void> pumpConnectPage(
    WidgetTester tester,
    FakeBleRepository ble,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bleRepositoryProvider.overrideWith((ref) => ble),
          rssiPollIntervalProvider.overrideWith((ref) => null),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          home: const ConnectPage(),
        ),
      ),
    );
  }

  testWidgets('shows two ConnectionCards (L and R) initially disconnected',
      (tester) async {
    final ble = FakeBleRepository(devices: const []);
    await pumpConnectPage(tester, ble);

    expect(find.text('Left wheel'), findsOneWidget);
    expect(find.text('Right wheel'), findsOneWidget);
    expect(find.text('Disconnected'), findsNWidgets(2));
  });

  testWidgets('shows empty-state hint when no devices found and not scanning',
      (tester) async {
    final ble = FakeBleRepository(devices: const []);
    await pumpConnectPage(tester, ble);

    expect(find.text('Tap Scan to find WheelAthlete sensors.'), findsOneWidget);
  });

  testWidgets('shows error banner when connect fails (no Info seeded)',
      (tester) async {
    final ble = FakeBleRepository(
      devices: [const FakeDevice(id: 'X1', name: 'WheelAthlete-?', rssi: -40)],
      // No infoFor entry → connect throws → error banner appears.
    );
    await pumpConnectPage(tester, ble);

    await tester.tap(find.byKey(ConnectPage.scanButtonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ConnectPage.connectKey('X1')));
    await tester.pumpAndSettle();

    // The error banner is a Card with an error icon — verify it renders.
    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
  });

  testWidgets('Scan button triggers scan and lists found devices', (tester) async {
    final ble = FakeBleRepository(
      devices: [
        const FakeDevice(id: 'L1', name: 'WheelAthlete-L', rssi: -42),
        const FakeDevice(id: 'R1', name: 'WheelAthlete-R', rssi: -55),
      ],
      infoFor: {
        'L1': const DeviceInfo(
          wheelId: WheelId.left,
          fwMajor: 1,
          fwMinor: 0,
          fwPatch: 0,
          accelRange: 0,
          gyroRange: 3,
          accelScale: 6.1e-5,
          gyroScale: 6.1e-2,
        ),
        'R1': const DeviceInfo(
          wheelId: WheelId.right,
          fwMajor: 1,
          fwMinor: 0,
          fwPatch: 0,
          accelRange: 0,
          gyroRange: 3,
          accelScale: 6.1e-5,
          gyroScale: 6.1e-2,
        ),
      },
    );
    await pumpConnectPage(tester, ble);

    await tester.tap(find.byKey(ConnectPage.scanButtonKey));
    await tester.pumpAndSettle();

    expect(find.text('WheelAthlete-L'), findsWidgets);
    expect(find.text('WheelAthlete-R'), findsWidgets);
  });

  testWidgets('tapping a found device connects and updates its ConnectionCard',
      (tester) async {
    final ble = FakeBleRepository(
      devices: [
        const FakeDevice(id: 'L1', name: 'WheelAthlete-L', rssi: -42),
      ],
      infoFor: {
        'L1': const DeviceInfo(
          wheelId: WheelId.left,
          fwMajor: 1,
          fwMinor: 0,
          fwPatch: 0,
          accelRange: 0,
          gyroRange: 3,
          accelScale: 6.1e-5,
          gyroScale: 6.1e-2,
        ),
      },
    );
    await pumpConnectPage(tester, ble);

    await tester.tap(find.byKey(ConnectPage.scanButtonKey));
    await tester.pumpAndSettle();

    // Tap the connect affordance for the first found device.
    await tester.tap(find.byKey(ConnectPage.connectKey('L1')));
    await tester.pumpAndSettle();

    // The Left ConnectionCard should now read Connected.
    final leftCard = find.ancestor(
      of: find.text('Left wheel'),
      matching: find.byType(Card),
    );
    expect(
      find.descendant(of: leftCard, matching: find.text('Connected')),
      findsOneWidget,
    );
  });
}
