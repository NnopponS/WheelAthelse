import 'package:flutter_test/flutter_test.dart';
import 'package:wheelsense/theme/theme.dart';
import 'package:wheelsense/widgets/connection_card.dart';

import '../helpers/pump.dart';

void main() {
  setUpAll(disableGoogleFontsFetching);

  testWidgets('connected card shows device name, battery and status',
      (tester) async {
    await pumpThemed(
      tester,
      const ConnectionCard(
        side: WheelSide.left,
        status: ConnectionStatus.connected,
        deviceName: 'WheelSense-L',
        batteryPercent: 82,
        rssi: -54,
      ),
    );
    expect(find.text('Left wheel'), findsOneWidget);
    expect(find.text('WheelSense-L'), findsOneWidget);
    expect(find.text('82%'), findsOneWidget);
    expect(find.text('-54 dBm'), findsOneWidget);
    expect(find.text('Connected'), findsOneWidget);
  });

  testWidgets('disconnected card shows placeholders, not telemetry',
      (tester) async {
    await pumpThemed(
      tester,
      const ConnectionCard(
        side: WheelSide.right,
        status: ConnectionStatus.disconnected,
      ),
    );
    expect(find.text('Right wheel'), findsOneWidget);
    expect(find.text('No device'), findsOneWidget);
    expect(find.text('Disconnected'), findsOneWidget);
    expect(find.text('--'), findsNWidgets(2)); // battery + signal placeholders
  });

  testWidgets('tapping the card invokes onTap', (tester) async {
    var taps = 0;
    await pumpThemed(
      tester,
      ConnectionCard(
        side: WheelSide.left,
        status: ConnectionStatus.connected,
        onTap: () => taps++,
      ),
    );
    await tester.tap(find.text('Left wheel'));
    expect(taps, 1);
  });
}
