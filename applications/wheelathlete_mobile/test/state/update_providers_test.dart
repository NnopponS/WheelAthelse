import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/state/update_providers.dart';
import 'package:wheelathlete/update/mobile_update_service.dart';

class FakeUpdateService extends MobileUpdateService {
  FakeUpdateService(this.manifest);

  final MobileUpdateManifest manifest;
  int checks = 0;

  @override
  Future<MobileUpdateManifest> check() async {
    checks += 1;
    return manifest;
  }

  @override
  void close() {}
}

MobileUpdateManifest fixtureManifest() => parseMobileUpdateManifest(
  utf8.encode(
    jsonEncode({
      'schema': 1,
      'version': '1.8.2',
      'channel': 'stable',
      'release_url':
          'https://github.com/NnopponS/WheelAthelse/releases/tag/v1.8.2',
      'notes': 'Updater test',
      'platforms': {
        'android': {
          'version': '1.8.2',
          'build': 11,
          'url':
              'https://github.com/NnopponS/WheelAthelse/releases/download/v1.8.2/WheelAthlete-Android-1.8.2.apk',
          'sha256': 'a' * 64,
          'size': 100,
        },
        'ios': {
          'version': '1.8.2',
          'url': 'https://github.com/NnopponS/WheelAthelse/releases/tag/v1.8.2',
          'store_managed': true,
        },
      },
    }),
  ),
);

void main() {
  test('manual check moves state to available without real network', () async {
    final fake = FakeUpdateService(fixtureManifest());
    final container = ProviderContainer(
      overrides: [mobileUpdateServiceProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);

    expect(
      container.read(mobileUpdateProvider).status,
      MobileUpdateStatus.idle,
    );
    await container.read(mobileUpdateProvider.notifier).check();

    final state = container.read(mobileUpdateProvider);
    expect(fake.checks, 1);
    expect(state.status, MobileUpdateStatus.available);
    expect(state.manifest?.version, '1.8.2');
    expect(state.updateAvailable, isTrue);
  });
}
