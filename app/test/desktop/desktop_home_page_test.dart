import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:wheelathlete/desktop/desktop_home_page.dart';
import 'package:wheelathlete/records/protocol_repository.dart';
import 'package:wheelathlete/records/storage_repository.dart';
import 'package:wheelathlete/state/ble_providers.dart';
import 'package:wheelathlete/state/protocol_providers.dart';
import 'package:wheelathlete/theme/theme.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<void> pumpDesktop(WidgetTester tester) async {
    final theme = ThemeModeController();
    addTearDown(theme.dispose);
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          protocolRepositoryProvider.overrideWith(
            (ref) => InMemoryProtocolRepository(),
          ),
          storageRepositoryProvider.overrideWith(
            (ref) => InMemoryStorageRepository(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: DesktopHomePage(themeController: theme, autoConnect: false),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('desktop shell exposes research navigation', (tester) async {
    await pumpDesktop(tester);

    for (final label in const [
      'Dashboard',
      'Connect',
      'Live',
      'Record',
      'Experiments',
      'Sessions',
      'Diagnostics',
    ]) {
      expect(find.text(label), findsWidgets);
    }
    expect(find.text('Research acquisition overview'), findsOneWidget);
    expect(find.textContaining('Daemon offline'), findsWidgets);
  });

  testWidgets('Live page states that preview is decoupled from raw stream', (
    tester,
  ) async {
    await pumpDesktop(tester);
    await tester.tap(find.byIcon(Icons.monitor_heart_outlined));
    await tester.pump();

    expect(find.text('Throttled live preview'), findsOneWidget);
    expect(
      find.textContaining('raw 50/100/200 Hz samples never cross into Flutter'),
      findsOneWidget,
    );
  });

  testWidgets('Diagnostics page exposes data-path counters and report export', (
    tester,
  ) async {
    await pumpDesktop(tester);
    await tester.tap(find.byIcon(Icons.troubleshoot_outlined));
    await tester.pump();

    expect(find.text('Acquisition diagnostics'), findsOneWidget);
    expect(find.text('Sequence gaps'), findsWidgets);
    expect(find.text('Queue high-water'), findsWidgets);
    expect(find.text('FIFO samples lost'), findsWidgets);
    expect(find.text('Export report'), findsOneWidget);
  });
}
