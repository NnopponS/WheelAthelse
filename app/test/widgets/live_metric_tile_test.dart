import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/theme/theme.dart';
import 'package:wheelathlete/widgets/live_metric_tile.dart';

import '../helpers/pump.dart';

void main() {
  setUpAll(disableGoogleFontsFetching);

  testWidgets('formats a positive value with a leading +', (tester) async {
    await pumpThemed(
      tester,
      const LiveMetricTile(label: 'ax', value: 1.234, unit: 'g'),
    );
    expect(find.text('+1.23'), findsOneWidget);
    expect(find.text('g'), findsOneWidget);
    expect(find.text('AX'), findsOneWidget); // label is upper-cased
  });

  testWidgets('formats a negative value with a leading -', (tester) async {
    await pumpThemed(
      tester,
      const LiveMetricTile(
        label: 'gz',
        value: -42.5,
        unit: '°/s',
        fractionDigits: 1,
      ),
    );
    expect(find.text('-42.5'), findsOneWidget);
  });

  testWidgets('honours fractionDigits', (tester) async {
    await pumpThemed(
      tester,
      const LiveMetricTile(
        label: 'ay',
        value: 0.1,
        unit: 'g',
        fractionDigits: 3,
      ),
    );
    expect(find.text('+0.100'), findsOneWidget);
  });

  testWidgets('tints the value with the wheel identity color', (tester) async {
    await pumpThemed(
      tester,
      const LiveMetricTile(
        label: 'ax',
        value: 1,
        unit: 'g',
        side: WheelSide.right,
      ),
    );
    final text = tester.widget<Text>(find.text('+1.00'));
    expect(text.style?.color, WheelAthleteColors.light.right.solid);
  });
}
