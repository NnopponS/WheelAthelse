import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheelsense/widgets/status_badge.dart';

import '../helpers/pump.dart';

void main() {
  setUpAll(disableGoogleFontsFetching);

  testWidgets('renders the label', (tester) async {
    await pumpThemed(tester, const StatusBadge(label: 'Connected'));
    expect(find.text('Connected'), findsOneWidget);
  });

  testWidgets('shows an icon when provided', (tester) async {
    await pumpThemed(
      tester,
      const StatusBadge(label: 'OK', icon: Icons.check_circle_rounded),
    );
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
  });

  testWidgets('renders no icon by default', (tester) async {
    await pumpThemed(tester, const StatusBadge(label: 'Plain'));
    expect(find.byType(Icon), findsNothing);
  });

  testWidgets('different tones produce different backgrounds', (tester) async {
    await pumpThemed(
      tester,
      const Column(
        children: [
          StatusBadge(label: 'a', tone: BadgeTone.success),
          StatusBadge(label: 'b', tone: BadgeTone.danger),
        ],
      ),
    );
    final containers = tester
        .widgetList<Container>(find.byType(Container))
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .map((d) => d.color)
        .toList();
    // Two distinct badge fills present.
    expect(containers.toSet().length, greaterThanOrEqualTo(2));
  });
}
