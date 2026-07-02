import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/theme/theme.dart';
import 'package:wheelathlete/ui/tag_editor_dialog.dart';

import '../helpers/pump.dart';

void main() {
  setUpAll(disableGoogleFontsFetching);

  Future<void> pumpDialog(
    WidgetTester tester, {
    required List<String> initialTags,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showTagEditorDialog(
                  context,
                  initialTags: initialTags,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  group('TagEditorDialog', () {
    testWidgets('shows existing tags as chips', (tester) async {
      await pumpDialog(tester, initialTags: ['good', 'athlete-A']);
      expect(find.text('good'), findsOneWidget);
      expect(find.text('athlete-A'), findsOneWidget);
    });

    testWidgets('shows a text field + Add button', (tester) async {
      await pumpDialog(tester, initialTags: const []);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Add'), findsOneWidget);
    });

    testWidgets('adding a tag appends it to the list', (tester) async {
      await pumpDialog(tester, initialTags: const []);
      await tester.enterText(find.byType(TextField), 'morning');
      await tester.tap(find.widgetWithText(TextButton, 'Add'));
      await tester.pumpAndSettle();
      expect(find.text('morning'), findsOneWidget);
    });

    testWidgets('tapping delete icon on a chip removes the tag',
        (tester) async {
      await pumpDialog(tester, initialTags: ['good', 'bad']);
      // Each chip has a delete icon.
      expect(find.byIcon(Icons.cancel), findsNWidgets(2));
      await tester.tap(find.byIcon(Icons.cancel).first);
      await tester.pumpAndSettle();
      // One chip removed.
      expect(find.byIcon(Icons.cancel), findsOneWidget);
    });

    testWidgets('Save returns the updated tag list', (tester) async {
      late List<String>? result;
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await showTagEditorDialog(
                      context,
                      initialTags: ['good'],
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'new-tag');
      await tester.tap(find.widgetWithText(TextButton, 'Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(result, ['good', 'new-tag']);
    });

    testWidgets('Cancel returns null', (tester) async {
      late List<String>? result = <String>['sentinel'];
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await showTagEditorDialog(
                      context,
                      initialTags: ['good'],
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(result, isNull);
    });

    testWidgets('empty + whitespace-only tags are ignored', (tester) async {
      await pumpDialog(tester, initialTags: const []);
      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.widgetWithText(TextButton, 'Add'));
      await tester.pumpAndSettle();
      // No chip added.
      expect(find.byIcon(Icons.cancel), findsNothing);
    });

    testWidgets('duplicate tags are not added', (tester) async {
      await pumpDialog(tester, initialTags: ['good']);
      await tester.enterText(find.byType(TextField), 'good');
      await tester.tap(find.widgetWithText(TextButton, 'Add'));
      await tester.pumpAndSettle();
      // Still only one 'good' chip.
      expect(find.text('good'), findsOneWidget);
    });
  });
}
