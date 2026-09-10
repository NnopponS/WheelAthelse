# WheelAthlete Windows Packaging

This folder contains the only supported Windows packaging path for the Python Research Edition.

## Inputs

- `../../../../VERSION` — coordinated product version
- `../../tools/pc_gui/` — PySide6 GUI
- `../../tools/pc_acquisition/` — acquisition daemon
- `../../../../assets/wheelathlete-logo.ico` — application/installer icon

## Prerequisites

- Python with the Windows app dependencies installed
- PyInstaller (`python -m pip install pyinstaller`)
- Inno Setup 6 installed at the standard per-user location
- Windows SDK `signtool.exe`, a trusted RSA certificate with the Code Signing EKU installed in the current user's certificate store, and an RFC3161 timestamp service for public packages

## Build

From the repository root:

```bat
applications\wheelathlete_windows\packaging\windows\build_installer.bat
```

The script builds the GUI, builds a standalone `WheelAthleteDaemon.exe`, bundles the daemon into the GUI distribution, creates a portable ZIP, then creates the Inno Setup installer.

For a trusted release, set the certificate thumbprint, its exact subject, and timestamp URL in the build environment:

```bat
set WHEELATHLETE_SIGN_CERT_SHA1=<40-hex-certificate-thumbprint>
set WHEELATHLETE_SIGN_CERT_SUBJECT=<exact-certificate-subject>
set WHEELATHLETE_TIMESTAMP_URL=https://<rfc3161-service>
applications\wheelathlete_windows\packaging\windows\build_installer.bat
```

The build signs every packaged `.exe`, `.dll`, `.pyd`, and `.ps1`, then uses Inno Setup's signing hook for both the generated uninstaller and final installer. It requires a valid timestamp on every executable component and the expected publisher on first-party files. Any partial signing configuration or failed check stops the build. The certificate and private key must never be added to the repository. With no signing variables, the script creates an explicitly unsigned local-development package; this does not fix Microsoft Defender download reputation or Application Control error 4551.

GitHub Actions uses secrets `WHEELATHLETE_SIGN_PFX_BASE64` and `WHEELATHLETE_SIGN_PFX_PASSWORD`, plus variables `WHEELATHLETE_SIGN_CERT_SUBJECT` and `WHEELATHLETE_TIMESTAMP_URL`. The release workflow is fail closed when any value is absent. A valid trusted signature addresses the normal Smart App Control trust path, but an organization may still enforce a narrower allowlist; no package can override that administrator policy.

## Outputs

Generated files are written to the ignored `applications/wheelathlete_windows/release/` directory:

- `WheelAthlete-<version>-portable.zip`
- `WheelAthleteSetup-<version>.exe`
- `SHA256SUMS.txt`
- `signing-report.json`

Intermediate PyInstaller files are written under ignored `applications/wheelathlete_windows/build/pyinstaller/`.

The GUI bundle includes the root `VERSION` file so the updater can identify the installed version. Inno Setup preserves one AppId across releases and understands `/AUTOUPDATE=1` so a verified in-app update can close the GUI, replace files, and relaunch WheelAthlete.

## Upgrade and uninstall behavior

Before upgrade or uninstall, setup runs `stop_installed_daemon.ps1` for the selected installation root. New daemons receive the explicit IPC shutdown request; an active recording is finalized and live acquisition stops before the daemon exits. For older layouts, the helper asks the daemon to end recording and live state before stopping only verified `WheelAthleteDaemon.exe` processes whose executable path is inside that installation. Setup blocks and shows the helper's actionable error when safe shutdown cannot be confirmed.

The application binaries, Start menu entry, desktop shortcut, and uninstall registration belong to the install. Recordings, logs, experiment presets, and custom model bundles under `Documents/WheelAthlete` are user data and survive upgrade and uninstall.

After uninstall, verify that no `WheelAthlete.exe` or installation-owned `WheelAthleteDaemon.exe` process remains, the selected installation directory and shortcuts are removed, and the WheelAthlete uninstall registration is gone. Do not delete `Documents/WheelAthlete` when checking cleanup.

Do not commit generated EXE/ZIP/build output. Commit only the packaging source in this folder.
