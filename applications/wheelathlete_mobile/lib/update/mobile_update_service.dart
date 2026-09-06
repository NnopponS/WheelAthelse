import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:wheelathlete/update/app_version.dart';

const _repoPathPrefix = '/NnopponS/WheelAthelse/';
const _releaseDownloadPrefix = '${_repoPathPrefix}releases/download/';
const _schemaVersion = 1;

enum MobileUpdatePlatform { android, ios }

class MobileUpdateException implements Exception {
  const MobileUpdateException(this.message);
  final String message;

  @override
  String toString() => message;
}

class SemanticVersion implements Comparable<SemanticVersion> {
  const SemanticVersion(this.major, this.minor, this.patch);

  final int major;
  final int minor;
  final int patch;

  factory SemanticVersion.parse(String value) {
    var raw = value.trim();
    if (raw.toLowerCase().startsWith('v')) raw = raw.substring(1);
    raw = raw.split('+').first.split('-').first;
    final parts = raw.split('.');
    if (parts.length != 3) {
      throw MobileUpdateException('Invalid semantic version: $value');
    }
    final numbers = parts.map(int.tryParse).toList(growable: false);
    if (numbers.any((part) => part == null)) {
      throw MobileUpdateException('Invalid semantic version: $value');
    }
    return SemanticVersion(numbers[0]!, numbers[1]!, numbers[2]!);
  }

  @override
  int compareTo(SemanticVersion other) {
    final left = (major, minor, patch);
    final right = (other.major, other.minor, other.patch);
    if (left.$1 != right.$1) return left.$1.compareTo(right.$1);
    if (left.$2 != right.$2) return left.$2.compareTo(right.$2);
    return left.$3.compareTo(right.$3);
  }

  @override
  bool operator ==(Object other) =>
      other is SemanticVersion &&
      major == other.major &&
      minor == other.minor &&
      patch == other.patch;

  @override
  int get hashCode => Object.hash(major, minor, patch);
}

class AndroidUpdateArtifact {
  const AndroidUpdateArtifact({
    required this.version,
    required this.build,
    required this.url,
    required this.sha256,
    required this.size,
  });

  final String version;
  final int build;
  final Uri url;
  final String sha256;
  final int size;
}

class IosUpdateArtifact {
  const IosUpdateArtifact({
    required this.version,
    required this.url,
    required this.storeManaged,
  });

  final String version;
  final Uri url;
  final bool storeManaged;
}

class MobileUpdateManifest {
  const MobileUpdateManifest({
    required this.version,
    required this.channel,
    required this.releaseUrl,
    required this.notes,
    required this.android,
    required this.ios,
  });

  final String version;
  final String channel;
  final Uri releaseUrl;
  final String notes;
  final AndroidUpdateArtifact android;
  final IosUpdateArtifact ios;
}

void _validateRepoUrl(Uri uri, {bool releaseDownload = false, String? suffix}) {
  if (uri.scheme != 'https' || uri.host != 'github.com') {
    throw const MobileUpdateException(
      'Update URLs must use github.com over HTTPS',
    );
  }
  final prefix = releaseDownload ? _releaseDownloadPrefix : _repoPathPrefix;
  if (!uri.path.startsWith(prefix)) {
    throw const MobileUpdateException(
      'Update URL is outside the WheelAthelse GitHub repository',
    );
  }
  if (suffix != null &&
      !uri.path.toLowerCase().endsWith(suffix.toLowerCase())) {
    throw MobileUpdateException('Update artifact must end with $suffix');
  }
}

MobileUpdateManifest parseMobileUpdateManifest(List<int> bytes) {
  late final Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes));
  } on Object catch (_) {
    throw const MobileUpdateException(
      'Update manifest is not valid UTF-8 JSON',
    );
  }
  if (decoded is! Map<String, dynamic> || decoded['schema'] != _schemaVersion) {
    throw const MobileUpdateException('Unsupported update manifest schema');
  }
  final version = (decoded['version'] as Object?)?.toString().trim() ?? '';
  SemanticVersion.parse(version);
  if (decoded['channel'] != 'stable') {
    throw const MobileUpdateException(
      'Only the stable update channel is accepted',
    );
  }
  final releaseUrl = Uri.tryParse(
    (decoded['release_url'] as Object?)?.toString() ?? '',
  );
  if (releaseUrl == null) {
    throw const MobileUpdateException('Release URL is invalid');
  }
  _validateRepoUrl(releaseUrl);

  final platforms = decoded['platforms'];
  if (platforms is! Map<String, dynamic>) {
    throw const MobileUpdateException('Update manifest is missing platforms');
  }
  final android = platforms['android'];
  final ios = platforms['ios'];
  if (android is! Map<String, dynamic> || ios is! Map<String, dynamic>) {
    throw const MobileUpdateException(
      'Update manifest is missing mobile artifacts',
    );
  }

  final androidVersion = (android['version'] as Object?)?.toString() ?? '';
  final androidBuild = android['build'];
  final androidUrl = Uri.tryParse(
    (android['url'] as Object?)?.toString() ?? '',
  );
  final androidSha =
      (android['sha256'] as Object?)?.toString().toLowerCase() ?? '';
  final androidSize = android['size'];
  if (androidVersion != version || androidBuild is! int || androidBuild <= 0) {
    throw const MobileUpdateException(
      'Android update version/build is invalid',
    );
  }
  if (androidUrl == null) {
    throw const MobileUpdateException('Android update URL is invalid');
  }
  _validateRepoUrl(androidUrl, releaseDownload: true, suffix: '.apk');
  if (androidSha.length != 64 ||
      !RegExp(r'^[0-9a-f]{64}$').hasMatch(androidSha)) {
    throw const MobileUpdateException('Android update SHA-256 is invalid');
  }
  if (androidSize is! int || androidSize <= 0) {
    throw const MobileUpdateException('Android update size is invalid');
  }

  final iosVersion = (ios['version'] as Object?)?.toString() ?? '';
  final iosUrl = Uri.tryParse((ios['url'] as Object?)?.toString() ?? '');
  if (iosVersion != version || iosUrl == null || iosUrl.scheme != 'https') {
    throw const MobileUpdateException('iOS update metadata is invalid');
  }

  return MobileUpdateManifest(
    version: version,
    channel: 'stable',
    releaseUrl: releaseUrl,
    notes: (decoded['notes'] as Object?)?.toString().trim() ?? '',
    android: AndroidUpdateArtifact(
      version: androidVersion,
      build: androidBuild,
      url: androidUrl,
      sha256: androidSha,
      size: androidSize,
    ),
    ios: IosUpdateArtifact(
      version: iosVersion,
      url: iosUrl,
      storeManaged: ios['store_managed'] == true,
    ),
  );
}

bool mobileUpdateAvailableFor(
  MobileUpdateManifest manifest, {
  required MobileUpdatePlatform platform,
  String currentVersion = wheelAthleteAppVersion,
  int currentBuild = wheelAthleteAppBuild,
}) {
  final current = SemanticVersion.parse(currentVersion);
  final remote = SemanticVersion.parse(manifest.version);
  final comparison = remote.compareTo(current);
  if (platform == MobileUpdatePlatform.android) {
    // Android's package installer requires a strictly increasing versionCode
    // even when the semantic versionName is newer.
    return comparison >= 0 && manifest.android.build > currentBuild;
  }
  return comparison > 0;
}

bool mobileUpdateAvailable(MobileUpdateManifest manifest) {
  final platform = Platform.isIOS
      ? MobileUpdatePlatform.ios
      : MobileUpdatePlatform.android;
  return mobileUpdateAvailableFor(manifest, platform: platform);
}

class MobileUpdateService {
  MobileUpdateService({HttpClient? httpClient})
    : _httpClient = httpClient ?? HttpClient();

  final HttpClient _httpClient;
  static const MethodChannel _androidChannel = MethodChannel(
    'wheelathlete/app_update',
  );

  Future<MobileUpdateManifest> check() async {
    final uri = Uri.parse(wheelAthleteUpdateManifestUrl);
    _validateRepoUrl(uri);
    final request = await _httpClient
        .getUrl(uri)
        .timeout(const Duration(seconds: 10));
    request.headers.set(
      HttpHeaders.userAgentHeader,
      'WheelAthlete-Mobile-Updater/1',
    );
    final response = await request.close().timeout(const Duration(seconds: 15));
    if (response.statusCode != HttpStatus.ok) {
      throw MobileUpdateException(
        'Update check failed with HTTP ${response.statusCode}',
      );
    }
    final builder = BytesBuilder(copy: false);
    var total = 0;
    await for (final chunk in response) {
      total += chunk.length;
      if (total > 1024 * 1024) {
        throw const MobileUpdateException(
          'Update manifest is unexpectedly large',
        );
      }
      builder.add(chunk);
    }
    return parseMobileUpdateManifest(builder.takeBytes());
  }

  Future<File> downloadAndroidApk(
    AndroidUpdateArtifact artifact, {
    ValueChanged<double>? onProgress,
  }) async {
    _validateRepoUrl(artifact.url, releaseDownload: true, suffix: '.apk');
    final temp = await getTemporaryDirectory();
    final directory = Directory(
      '${temp.path}${Platform.pathSeparator}wheelathlete_updates',
    );
    await directory.create(recursive: true);
    final file = File(
      '${directory.path}${Platform.pathSeparator}'
      'WheelAthlete-${artifact.version}-${artifact.build}.apk',
    );
    final partial = File('${file.path}.part');
    if (await partial.exists()) await partial.delete();

    try {
      final request = await _httpClient
          .getUrl(artifact.url)
          .timeout(const Duration(seconds: 15));
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'WheelAthlete-Mobile-Updater/1',
      );
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw MobileUpdateException(
          'APK download failed with HTTP ${response.statusCode}',
        );
      }
      var written = 0;
      final sink = partial.openWrite();
      try {
        await for (final chunk in response) {
          written += chunk.length;
          if (written > artifact.size) {
            throw const MobileUpdateException(
              'Downloaded APK exceeds manifest size',
            );
          }
          sink.add(chunk);
          onProgress?.call((written / artifact.size).clamp(0, 1));
        }
      } finally {
        await sink.close();
      }
      if (written != artifact.size) {
        throw MobileUpdateException(
          'Downloaded APK size mismatch: expected ${artifact.size}, got $written',
        );
      }
      final digest = await sha256.bind(partial.openRead()).first;
      if (digest.toString().toLowerCase() != artifact.sha256.toLowerCase()) {
        throw const MobileUpdateException('Downloaded APK SHA-256 mismatch');
      }
      if (await file.exists()) await file.delete();
      return partial.rename(file.path);
    } on Object catch (_) {
      if (await partial.exists()) await partial.delete();
      rethrow;
    }
  }

  Future<bool> canInstallAndroidPackages() async {
    if (!Platform.isAndroid) return false;
    return await _androidChannel.invokeMethod<bool>('canInstallPackages') ??
        false;
  }

  Future<void> openAndroidInstallPermission() async {
    if (!Platform.isAndroid) return;
    await _androidChannel.invokeMethod<void>('openInstallPermission');
  }

  Future<void> installAndroidApk(File apk) async {
    if (!Platform.isAndroid) {
      throw const MobileUpdateException(
        'APK installation is only available on Android',
      );
    }
    await _androidChannel.invokeMethod<void>('installApk', {'path': apk.path});
  }

  Future<void> openIosStore(IosUpdateArtifact artifact) async {
    if (!await launchUrl(artifact.url, mode: LaunchMode.externalApplication)) {
      throw const MobileUpdateException('Could not open the iOS update page');
    }
  }

  void close() => _httpClient.close(force: true);
}
