import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wheelathlete/update/mobile_update_service.dart';

enum MobileUpdateStatus {
  idle,
  checking,
  current,
  available,
  downloading,
  permissionRequired,
  readyToInstall,
  storeOpened,
  error,
}

class MobileUpdateState {
  const MobileUpdateState({
    this.status = MobileUpdateStatus.idle,
    this.manifest,
    this.downloadedApk,
    this.progress = 0,
    this.message = '',
  });

  final MobileUpdateStatus status;
  final MobileUpdateManifest? manifest;
  final File? downloadedApk;
  final double progress;
  final String message;

  bool get updateAvailable =>
      manifest != null && mobileUpdateAvailable(manifest!);

  MobileUpdateState copyWith({
    MobileUpdateStatus? status,
    Object? manifest = _unset,
    Object? downloadedApk = _unset,
    double? progress,
    String? message,
  }) => MobileUpdateState(
    status: status ?? this.status,
    manifest: identical(manifest, _unset)
        ? this.manifest
        : manifest as MobileUpdateManifest?,
    downloadedApk: identical(downloadedApk, _unset)
        ? this.downloadedApk
        : downloadedApk as File?,
    progress: progress ?? this.progress,
    message: message ?? this.message,
  );

  static const Object _unset = Object();
}

final mobileUpdateServiceProvider = Provider<MobileUpdateService>((ref) {
  final service = MobileUpdateService();
  ref.onDispose(service.close);
  return service;
});

class MobileUpdateNotifier extends Notifier<MobileUpdateState> {
  Timer? _initialTimer;
  Timer? _timer;
  bool _busy = false;

  @override
  MobileUpdateState build() {
    ref.onDispose(() {
      _initialTimer?.cancel();
      _timer?.cancel();
    });
    return const MobileUpdateState();
  }

  void startAutomaticChecks() {
    if (!kReleaseMode && !kProfileMode) return;
    if (_timer != null || _initialTimer != null) return;
    _initialTimer = Timer(const Duration(seconds: 2), () {
      _initialTimer = null;
      check();
    });
    _timer = Timer.periodic(const Duration(hours: 6), (_) => check());
  }

  Future<void> check() async {
    if (_busy) return;
    _busy = true;
    state = state.copyWith(
      status: MobileUpdateStatus.checking,
      message: 'Checking GitHub Releases...',
      progress: 0,
    );
    try {
      final manifest = await ref.read(mobileUpdateServiceProvider).check();
      final available = mobileUpdateAvailable(manifest);
      state = MobileUpdateState(
        status: available
            ? MobileUpdateStatus.available
            : MobileUpdateStatus.current,
        manifest: manifest,
        message: available
            ? 'WheelAthlete ${manifest.version} is available'
            : 'WheelAthlete is up to date',
      );
    } on Object catch (error) {
      state = state.copyWith(
        status: MobileUpdateStatus.error,
        message: error.toString(),
      );
    } finally {
      _busy = false;
    }
  }

  Future<void> beginUpdate() async {
    if (_busy) return;
    final manifest = state.manifest;
    if (manifest == null || !mobileUpdateAvailable(manifest)) {
      await check();
      return;
    }
    final service = ref.read(mobileUpdateServiceProvider);
    if (Platform.isIOS) {
      try {
        await service.openIosStore(manifest.ios);
        state = state.copyWith(
          status: MobileUpdateStatus.storeOpened,
          message: 'Opened the App Store/TestFlight update page',
        );
      } on Object catch (error) {
        state = state.copyWith(
          status: MobileUpdateStatus.error,
          message: error.toString(),
        );
      }
      return;
    }
    if (!Platform.isAndroid) {
      state = state.copyWith(
        status: MobileUpdateStatus.error,
        message: 'Mobile self-update is supported on Android and iOS only',
      );
      return;
    }

    _busy = true;
    state = state.copyWith(
      status: MobileUpdateStatus.downloading,
      message: 'Downloading verified APK...',
      progress: 0,
    );
    try {
      final apk = await service.downloadAndroidApk(
        manifest.android,
        onProgress: (progress) {
          state = state.copyWith(
            status: MobileUpdateStatus.downloading,
            progress: progress,
            message: 'Downloading verified APK... ${(progress * 100).round()}%',
          );
        },
      );
      state = state.copyWith(
        downloadedApk: apk,
        progress: 1,
        status: MobileUpdateStatus.readyToInstall,
        message:
            'APK verified and ready to install. Tap Install update to continue.',
      );
    } on Object catch (error) {
      state = state.copyWith(
        status: MobileUpdateStatus.error,
        message: error.toString(),
      );
    } finally {
      _busy = false;
    }
  }

  Future<void> installDownloadedAndroidApk() async {
    final apk = state.downloadedApk;
    if (apk == null) {
      state = state.copyWith(
        status: MobileUpdateStatus.error,
        message: 'No verified APK is ready to install',
      );
      return;
    }
    final service = ref.read(mobileUpdateServiceProvider);
    try {
      if (!await service.canInstallAndroidPackages()) {
        state = state.copyWith(
          status: MobileUpdateStatus.permissionRequired,
          message:
              "Allow 'Install unknown apps' for WheelAthlete, then return and tap Install update again.",
        );
        await service.openAndroidInstallPermission();
        return;
      }
      await service.installAndroidApk(apk);
      state = state.copyWith(
        status: MobileUpdateStatus.readyToInstall,
        message:
            'Android installer opened. Confirm the system update to continue.',
      );
    } on Object catch (error) {
      state = state.copyWith(
        status: MobileUpdateStatus.error,
        message: error.toString(),
      );
    }
  }
}

final mobileUpdateProvider =
    NotifierProvider<MobileUpdateNotifier, MobileUpdateState>(
      MobileUpdateNotifier.new,
    );
