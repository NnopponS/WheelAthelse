import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/ble/ble_repository.dart';
import 'package:wheelathlete/records/protocol_repository.dart';
import 'package:wheelathlete/records/storage_repository.dart';
import 'package:wheelathlete/state/ble_providers.dart';
import 'package:wheelathlete/state/protocol_providers.dart';
import 'package:wheelathlete/theme/theme.dart';
import 'package:wheelathlete/ui/home_page.dart';

import '../helpers/pump.dart';

void main() {
  setUpAll(disableGoogleFontsFetching);

  testWidgets('home exposes software update dialog without network at startup', (
    tester,
  ) async {
    final theme = ThemeModeController();
    addTearDown(theme.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bleRepositoryProvider.overrideWith(
            (_) => FakeBleRepository(devices: const []),
          ),
          protocolRepositoryProvider.overrideWith(
            (_) => InMemoryProtocolRepository(),
          ),
          storageRepositoryProvider.overrideWith(
            (_) => InMemoryStorageRepository(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: HomePage(themeController: theme),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('softwareUpdateButton')), findsOneWidget);
    await tester.tap(find.byKey(const Key('softwareUpdateButton')));
    await tester.pumpAndSettle();

    expect(find.text('Software update'), findsOneWidget);
    expect(find.text('Installed: WheelAthlete 1.8.0 (build 10)'), findsOneWidget);
    expect(find.byKey(const Key('softwareUpdateActionButton')), findsOneWidget);
  });
}
