import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/ble/ble_repository.dart';
import 'package:wheelathlete/desktop/desktop_acquisition_providers.dart';
import 'package:wheelathlete/state/ble_providers.dart';

void main() {
  test('existing production BLE provider remains FlutterBluePlus for mobile', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      container.read(bleRepositoryProvider),
      isA<FlutterBluePlusBleRepository>(),
    );
  });

  test('desktop daemon provider is opt-in and starts disconnected', () {
    var factoryReads = 0;
    final container = ProviderContainer(
      overrides: [
        desktopDaemonClientFactoryProvider.overrideWithValue(() async {
          factoryReads++;
          throw StateError('must not be created until connect is requested');
        }),
      ],
    );
    addTearDown(container.dispose);

    final state = container.read(desktopAcquisitionProvider);
    expect(state.connected, isFalse);
    expect(state.status, isEmpty);
    expect(factoryReads, 0);
  });
}
