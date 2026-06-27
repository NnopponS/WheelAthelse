import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheelsense/widgets/primary_action_button.dart';

import '../helpers/pump.dart';

void main() {
  setUpAll(disableGoogleFontsFetching);

  testWidgets('invokes onPressed when tapped', (tester) async {
    var taps = 0;
    await pumpThemed(
      tester,
      PrimaryActionButton(
        label: 'Start recording',
        intent: ActionIntent.start,
        onPressed: () => taps++,
      ),
    );
    await tester.tap(find.text('Start recording'));
    expect(taps, 1);
  });

  testWidgets('busy state shows a spinner and blocks taps', (tester) async {
    var taps = 0;
    await pumpThemed(
      tester,
      PrimaryActionButton(
        label: 'Syncing',
        busy: true,
        onPressed: () => taps++,
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    // Label is replaced by the spinner while busy.
    expect(find.text('Syncing'), findsNothing);
    await tester.tap(find.byType(PrimaryActionButton));
    expect(taps, 0);
  });

  testWidgets('null onPressed disables the button', (tester) async {
    await pumpThemed(
      tester,
      const PrimaryActionButton(label: 'Disabled', onPressed: null),
    );
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });
}
