# WheelAthlete v1.8.2 release

WheelAthlete 1.8.2 is a **Windows-first** release line. The current public GitHub Release is source-only until trusted Windows signing is configured. No mobile binary or mobile update offer belongs to this release.

## Stable Windows update manifest

Installed Windows clients use:

```text
https://github.com/NnopponS/WheelAthelse/releases/latest/download/latest.json
```

A source-only Release does not publish `latest.json`, so installed clients receive no update offer. When a trusted signed Windows release is available, the manifest contains the signed installer URL, exact byte size and SHA-256. The client accepts only HTTPS GitHub Release URLs belonging to this repository and verifies both size and hash before installation.

## Public signing requirements

The release workflow requires:

```text
GitHub secret:   WHEELATHLETE_SIGN_PFX_BASE64
GitHub secret:   WHEELATHLETE_SIGN_PFX_PASSWORD
GitHub variable: WHEELATHLETE_TIMESTAMP_URL
GitHub variable: WHEELATHLETE_SIGN_CERT_SUBJECT
```

The PFX must contain exactly one usable private-key signing identity. The build validates an RSA certificate with Code Signing EKU, current validity and the exact expected publisher subject. It signs/verifies packaged EXE/DLL/PYD files and the installed PowerShell helper, signs the generated Inno Setup uninstaller and outer installer, requires timestamps, and writes `signing-report.json` plus `SHA256SUMS.txt`.

Missing or incomplete signing configuration fails closed. Do not commit a PFX, password, private key or certificate material to the repository.

## Release gates

Before publishing Windows binaries:

1. `python scripts/verify_project.py` passes.
2. The complete Windows application/acquisition test suite passes at the exact release commit.
3. Release/manifest generator checks pass.
4. Maintained firmware host tests/builds pass for the intended release identity.
5. Installer lifecycle behavior remains safe: install/upgrade/uninstall/reinstall, graceful daemon shutdown and user-data preservation.
6. Every executable component in `signing-report.json` is valid/timestamped as required and `public_release_ready=true`.
7. The final diff contains no recordings, private paths, credentials, generated packages, new mobile application source changes or `BiWheel3D` files.

Physical L/R/C acceptance remains a separate hardware evidence gate. Source/build tests must not be presented as physical RF/orientation/accuracy validation.

## Signed assets when the trust gate is available

```text
WheelAthleteSetup-1.8.2.exe
WheelAthlete-1.8.2-portable.zip
SHA256SUMS.txt
signing-report.json
latest.json
```

Until trusted signing exists, the v1.8.2 page should contain GitHub's source archives only.

## Branch and version policy

`main` is the integrated source line. `release/main-v1.8.2` is the public release branch pointing at the exact tested v1.8.2 commit. Historical version tags are retained for traceability; obsolete remote development/release branches do not need to remain visible after their work is fully merged.

See [RELEASE_NOTES_1.8.2.md](RELEASE_NOTES_1.8.2.md) and [`../applications/wheelathlete_windows/packaging/windows/README.md`](../applications/wheelathlete_windows/packaging/windows/README.md).
