import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/widgets/mark_event_button.dart';

import '../helpers/pump.dart';

void main() {
  setUpAll(disableGoogleFontsFetching);

  testWidgets('singular vs plural marker count label', (tester) async {
    await pumpThemed(tester, MarkEventButton(markerCount: 1, onPressed: () {}));
    expect(find.text('1 marker'), findsOneWidget);

    await pumpThemed(tester, MarkEventButton(markerCount: 3, onPressed: () {}));
    expect(find.text('3 markers'), findsOneWidget);
  });

  testWidgets('invokes onPressed when enabled', (tester) async {
    var taps = 0;
    await pumpThemed(tester, MarkEventButton(onPressed: () => taps++));
    await tester.tap(find.byIcon(Icons.flag_rounded));
    expect(taps, 1);
  });

  testWidgets('does not invoke onPressed when disabled', (tester) async {
    var taps = 0;
    await pumpThemed(
      tester,
      MarkEventButton(enabled: false, onPressed: () => taps++),
    );
    await tester.tap(find.byIcon(Icons.flag_rounded));
    expect(taps, 0);
  });
}
