import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheelsense/widgets/session_list_item.dart';

import '../helpers/pump.dart';

void main() {
  setUpAll(disableGoogleFontsFetching);

  testWidgets('renders title, subtitle and metadata badges', (tester) async {
    await pumpThemed(
      tester,
      const SessionListItem(
        title: 'session_a1f3',
        subtitle: 'trial_03',
        duration: Duration(minutes: 2, seconds: 14),
        sampleCount: 12840,
        markerCount: 4,
        syncQuality: '±0.8 ms',
      ),
    );
    expect(find.text('session_a1f3'), findsOneWidget);
    expect(find.text('trial_03'), findsOneWidget);
    expect(find.text('2m 14s'), findsOneWidget);
    expect(find.text('12.8k samples'), findsOneWidget);
    expect(find.text('4 marks'), findsOneWidget);
    expect(find.text('sync ±0.8 ms'), findsOneWidget);
  });

  testWidgets('hides marker badge when count is zero', (tester) async {
    await pumpThemed(
      tester,
      const SessionListItem(title: 's', subtitle: 't', markerCount: 0),
    );
    expect(find.textContaining('marks'), findsNothing);
  });

  testWidgets('share button calls onShare', (tester) async {
    var shared = false;
    await pumpThemed(
      tester,
      SessionListItem(
        title: 's',
        subtitle: 't',
        onShare: () => shared = true,
      ),
    );
    await tester.tap(find.byIcon(Icons.ios_share_rounded));
    expect(shared, isTrue);
  });
}
