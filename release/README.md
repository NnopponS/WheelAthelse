# WheelAthlete release and automatic updates

WheelAthlete Mobile and WheelAthlete Windows consume one stable GitHub Releases manifest:

```text
https://github.com/NnopponS/WheelAthelse/releases/latest/download/latest.json
```

`latest.json` is generated only after the Android APK and Windows installer have been built. Each downloadable artifact records its exact byte size and SHA-256 digest. Both clients reject malformed manifests, non-HTTPS artifacts, downloads outside the official `NnopponS/WheelAthelse` GitHub Releases path, size mismatches, and hash mismatches.

## Platform behavior

- **Android:** the app downloads the verified APK into its private cache and opens Android's system package installer. The user must approve the update. Direct GitHub distribution may require enabling **Install unknown apps** for WheelAthlete. Installation is never started while Live preview, countdown, or recording is active.
- **iOS:** the app checks the same manifest, but installation is App Store/TestFlight managed. Set the GitHub repository variable `WHEELATHLETE_IOS_UPDATE_URL` to the production App Store or TestFlight URL when one is available.
- **Windows:** only an Inno-installed PyInstaller build self-installs. It downloads the installer, verifies size + SHA-256, refuses installation during active acquisition, exits the GUI, runs Inno Setup with `/AUTOUPDATE=1`, and relaunches WheelAthlete. Source and portable builds may check releases manually but do not replace themselves.

## Android release signing

Android will only accept an in-place update when every release is signed by the same key and has a strictly increasing `versionCode`. The tag workflow therefore requires these GitHub Actions secrets and fails instead of silently producing an incompatible public APK:

```text
ANDROID_KEYSTORE_BASE64
ANDROID_KEYSTORE_PASSWORD
ANDROID_KEY_ALIAS
ANDROID_KEY_PASSWORD
```

`ANDROID_KEYSTORE_BASE64` is the persistent release keystore encoded as base64. Never commit the keystore or its passwords to this repository. Local `flutter build apk --release` can still fall back to the debug key for development, but that APK is **not** suitable for the public auto-update channel.

If users already installed a debug-signed APK, a differently signed production APK cannot update it in place. Preserve/export important local research sessions before migrating those devices to the permanent production signing key.

## Publishing a release

1. Update the application version/build as appropriate. The root `VERSION` and Flutter semantic version must match. Android's build number after `+` must increase.
2. Commit the release-ready source on the non-`main` release branch used by the project.
3. Create the release tag `v<version>`. Until GitHub Android signing secrets are configured, publish signed release artifacts from the protected local release key instead of triggering CI from a tag.
4. When manually dispatched after signing secrets are configured, `.github/workflows/release.yml` runs the Flutter analyzer/tests, Android release build, Windows Python tests/compile checks, PyInstaller/Inno Setup packaging, and generates `latest.json` from the exact artifacts.
5. The workflow publishes:

```text
WheelAthlete-Android-<version>.apk
WheelAthleteSetup-<version>.exe
latest.json
```

## Bootstrap limitation

A build that predates the updater cannot discover or install its first update by itself. Install the first updater-enabled production release manually once. All later compatible releases can use the in-app update flow.
