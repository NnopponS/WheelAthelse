import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/widgets/session_list_item.dart';

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

  testWidgets('formats sub-1000 sample counts without k suffix', (tester) async {
    await pumpThemed(
      tester,
      const SessionListItem(
        title: 's',
        subtitle: 't',
        duration: Duration(seconds: 5),
        sampleCount: 742,
      ),
    );
    expect(find.text('742 samples'), findsOneWidget);
    expect(find.text('5s'), findsOneWidget);
  });

  testWidgets('delete button calls onDelete', (tester) async {
    var deleted = false;
    await pumpThemed(
      tester,
      SessionListItem(
        title: 's',
        subtitle: 't',
        onDelete: () => deleted = true,
      ),
    );
    expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    expect(deleted, isTrue);
  });

  testWidgets('hides delete button when onDelete is null', (tester) async {
    await pumpThemed(
      tester,
      const SessionListItem(title: 's', subtitle: 't'),
    );
    expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
  });
}
