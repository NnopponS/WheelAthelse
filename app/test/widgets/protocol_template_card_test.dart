import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/records/protocol_template.dart';
import 'package:wheelathlete/state/experiment_tracker_providers.dart';
import 'package:wheelathlete/widgets/protocol_template_card.dart';

import '../helpers/pump.dart';

void main() {
  setUpAll(disableGoogleFontsFetching);

  ExperimentProgress makeProgress({
    String name = '20m Sprint',
    String? description = 'Max effort from standing start',
    int target = 5,
    int sessions = 2,
    DateTime? lastDate,
  }) => ExperimentProgress(
    template: ProtocolTemplate(
      id: 't1',
      name: name,
      description: description,
      topicName: 'sprint_20m',
      targetTrialCount: target,
      createdAt: DateTime(2026, 1, 1),
    ),
    sessionCount: sessions,
    lastSessionDate: lastDate,
  );

  testWidgets('renders name, description, progress bar and count', (
    tester,
  ) async {
    await pumpThemed(
      tester,
      ProtocolTemplateCard(
        progress: makeProgress(sessions: 3, lastDate: DateTime(2026, 6, 15)),
      ),
    );
    expect(find.text('20m Sprint'), findsOneWidget);
    expect(find.text('Max effort from standing start'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('3 / 5 trials'), findsOneWidget);
    expect(find.text('2026-06-15'), findsOneWidget);
  });

  testWidgets('hides description when null', (tester) async {
    await pumpThemed(
      tester,
      ProtocolTemplateCard(progress: makeProgress(description: null)),
    );
    expect(find.text('20m Sprint'), findsOneWidget);
    expect(find.text('Max effort from standing start'), findsNothing);
  });

  testWidgets('hides last session date when null', (tester) async {
    await pumpThemed(
      tester,
      ProtocolTemplateCard(progress: makeProgress(lastDate: null)),
    );
    expect(find.textContaining('2026-'), findsNothing);
  });

  testWidgets('onTap fires when card is tapped', (tester) async {
    var tapped = false;
    await pumpThemed(
      tester,
      ProtocolTemplateCard(
        progress: makeProgress(),
        onTap: () => tapped = true,
      ),
    );
    await tester.tap(find.byType(ProtocolTemplateCard));
    await tester.pump();
    expect(tapped, isTrue);
  });
}
