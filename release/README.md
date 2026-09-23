# WheelAthlete v1.8.4 release

WheelAthlete v1.8.4 is a **Windows-first** release. This release publishes signed Windows assets only; Android/mobile source and binaries are outside its scope.

The release workflow runs only for the exact `v1.8.4` tag. It fails closed when trusted signing configuration is missing or the Windows signing report does not mark the installer ready. It publishes no unsigned installer or stable update manifest.

## Stable Windows update manifest

Installed Windows clients use:

```text
https://github.com/NnopponS/WheelAthelse/releases/latest/download/latest.json
```

The manifest describes the signed installer, exact byte size, SHA-256 and release URL. The client accepts only HTTPS GitHub Release URLs belonging to this repository and rejects manifests that do not mark the Windows artifact as signed.

## Public signing requirements

The release workflow requires:

```text
GitHub secret:   WHEELATHLETE_SIGN_PFX_BASE64
GitHub secret:   WHEELATHLETE_SIGN_PFX_PASSWORD
GitHub variable: WHEELATHLETE_TIMESTAMP_URL
GitHub variable: WHEELATHLETE_SIGN_CERT_SUBJECT
```

The PFX must contain exactly one usable private-key signing identity. The build validates an RSA certificate with Code Signing EKU, current validity and the exact expected publisher subject. It signs and verifies packaged executable components and the generated uninstaller/installer, requires timestamps, and writes a signing report.

Never commit a PFX, password, private key or certificate material to the repository.

## Release gates

Before publishing Windows binaries:

1. `python scripts/verify_project.py` passes.
2. The complete Windows application/acquisition test suite passes at the exact release commit.
3. Release-manifest generator checks pass.
4. Maintained firmware host tests and builds pass for the intended release identity.
5. Installer lifecycle behavior remains safe: install/upgrade/uninstall/reinstall, graceful daemon shutdown and user-data preservation.
6. Every executable component is valid and timestamped as required, and `public_release_ready=true`.
7. The final diff contains no recordings, private logs, absolute user paths, credentials, generated packages, mobile changes or `BiWheel3D` files.

Physical L/R/C acceptance is recorded separately. Software/build checks are not physical RF, orientation or trajectory-accuracy evidence.

## Signed Windows assets

```text
WheelAthleteSetup-1.8.4.exe
WheelAthlete-1.8.4-portable.zip
SHA256SUMS.txt
windows-signing-report.json
latest.json
```

## Branch and version policy

`main` is the integrated source line. `release/main-v1.8.4` must point at the exact tested release commit. Do not force-push `main`. Historical tags remain for traceability.

See [RELEASE_NOTES_1.8.4.md](RELEASE_NOTES_1.8.4.md) and [`../applications/wheelathlete_windows/packaging/windows/README.md`](../applications/wheelathlete_windows/packaging/windows/README.md).
