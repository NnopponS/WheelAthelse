import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/update/mobile_update_service.dart';

List<int> manifestBytes({
  String version = '1.8.2',
  int build = 11,
  String? androidUrl,
  String? androidSha,
}) {
  final value = <String, Object?>{
    'schema': 1,
    'version': version,
    'channel': 'stable',
    'release_url': 'https://github.com/NnopponS/WheelAthelse/releases/tag/v$version',
    'notes': 'Updater test release',
    'platforms': <String, Object?>{
      'android': <String, Object?>{
        'version': version,
        'build': build,
        'url': androidUrl ??
            'https://github.com/NnopponS/WheelAthelse/releases/download/v$version/WheelAthlete-Android-$version.apk',
        'sha256': androidSha ?? 'a' * 64,
        'size': 123456,
      },
      'windows': <String, Object?>{
        'version': version,
        'url': 'https://github.com/NnopponS/WheelAthelse/releases/download/v$version/WheelAthleteSetup-$version.exe',
        'sha256': 'b' * 64,
        'size': 654321,
      },
      'ios': <String, Object?>{
        'version': version,
        'url': 'https://github.com/NnopponS/WheelAthelse/releases/tag/v$version',
        'store_managed': true,
      },
    },
  };
  return utf8.encode(jsonEncode(value));
}

void main() {
  test('parses the shared stable manifest and Android artifact', () {
    final manifest = parseMobileUpdateManifest(manifestBytes());
    expect(manifest.version, '1.8.2');
    expect(manifest.channel, 'stable');
    expect(manifest.android.build, 11);
    expect(manifest.android.url.path, endsWith('.apk'));
    expect(manifest.android.sha256, 'a' * 64);
    expect(manifest.ios.storeManaged, isTrue);
  });

  test('Android update requires non-decreasing semver and higher build', () {
    final sameVersionHigherBuild = parseMobileUpdateManifest(
      manifestBytes(version: '1.8.1', build: 11),
    );
    expect(
      mobileUpdateAvailableFor(
        sameVersionHigherBuild,
        platform: MobileUpdatePlatform.android,
        currentVersion: '1.8.1',
        currentBuild: 10,
      ),
      isTrue,
    );

    final newerVersion = parseMobileUpdateManifest(
      manifestBytes(version: '1.8.2', build: 11),
    );
    expect(
      mobileUpdateAvailableFor(
        newerVersion,
        platform: MobileUpdatePlatform.android,
        currentVersion: '1.8.1',
        currentBuild: 10,
      ),
      isTrue,
    );

    final oldVersion = parseMobileUpdateManifest(
      manifestBytes(version: '1.8.0', build: 99),
    );
    expect(
      mobileUpdateAvailableFor(
        oldVersion,
        platform: MobileUpdatePlatform.android,
        currentVersion: '1.8.1',
        currentBuild: 10,
      ),
      isFalse,
    );
  });

  test('iOS update is semantic-version based and store managed', () {
    final newer = parseMobileUpdateManifest(manifestBytes(version: '1.8.2'));
    expect(
      mobileUpdateAvailableFor(
        newer,
        platform: MobileUpdatePlatform.ios,
        currentVersion: '1.8.1',
        currentBuild: 10,
      ),
      isTrue,
    );
    final same = parseMobileUpdateManifest(manifestBytes(version: '1.8.1'));
    expect(
      mobileUpdateAvailableFor(
        same,
        platform: MobileUpdatePlatform.ios,
        currentVersion: '1.8.1',
        currentBuild: 10,
      ),
      isFalse,
    );
  });

  test('rejects Android artifacts outside official GitHub release path', () {
    expect(
      () => parseMobileUpdateManifest(
        manifestBytes(
          androidUrl: 'https://evil.example/WheelAthlete-Android-1.8.2.apk',
        ),
      ),
      throwsA(isA<MobileUpdateException>()),
    );
    expect(
      () => parseMobileUpdateManifest(
        manifestBytes(
          androidUrl: 'http://github.com/NnopponS/WheelAthelse/releases/download/v1.8.2/WheelAthlete-Android-1.8.2.apk',
        ),
      ),
      throwsA(isA<MobileUpdateException>()),
    );
  });

  test('rejects malformed Android SHA-256 and unstable channel', () {
    expect(
      () => parseMobileUpdateManifest(manifestBytes(androidSha: 'xyz')),
      throwsA(isA<MobileUpdateException>()),
    );

    final decoded = jsonDecode(utf8.decode(manifestBytes())) as Map<String, dynamic>;
    decoded['channel'] = 'beta';
    expect(
      () => parseMobileUpdateManifest(utf8.encode(jsonEncode(decoded))),
      throwsA(isA<MobileUpdateException>()),
    );
  });
}
