import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/widgets/state_views.dart';

import '../helpers/pump.dart';

void main() {
  setUpAll(disableGoogleFontsFetching);

  testWidgets('EmptyState renders title/message and fires action',
      (tester) async {
    var tapped = false;
    await pumpThemed(
      tester,
      EmptyState(
        title: 'No sessions yet',
        message: 'Connect both wheels.',
        actionLabel: 'Scan',
        onAction: () => tapped = true,
      ),
    );
    expect(find.text('No sessions yet'), findsOneWidget);
    expect(find.text('Connect both wheels.'), findsOneWidget);
    await tester.tap(find.text('Scan'));
    expect(tapped, isTrue);
  });

  testWidgets('EmptyState hides action when no callback given',
      (tester) async {
    await pumpThemed(
      tester,
      const EmptyState(title: 'Empty', actionLabel: 'Ignored'),
    );
    expect(find.text('Ignored'), findsNothing);
  });

  testWidgets('LoadingState shows spinner and message', (tester) async {
    await pumpThemed(tester, const LoadingState(message: 'Scanning…'));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Scanning…'), findsOneWidget);
  });

  testWidgets('ErrorState fires retry', (tester) async {
    var retried = false;
    await pumpThemed(
      tester,
      ErrorState(
        title: 'Lost connection',
        onRetry: () => retried = true,
      ),
    );
    expect(find.text('Lost connection'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    expect(retried, isTrue);
  });

  testWidgets('ErrorState omits retry button without callback',
      (tester) async {
    await pumpThemed(tester, const ErrorState(title: 'Boom'));
    expect(find.text('Try again'), findsNothing);
  });

  testWidgets('ErrorState renders message when provided', (tester) async {
    await pumpThemed(
      tester,
      const ErrorState(
        title: 'Lost connection',
        message: 'The right wheel dropped off. Move closer and retry.',
      ),
    );
    expect(find.text('Lost connection'), findsOneWidget);
    expect(
      find.text('The right wheel dropped off. Move closer and retry.'),
      findsOneWidget,
    );
  });
}
