# WheelAthlete v1.8.2 Windows release

Version 1.8.2 distributes the Windows Research Application only. Flutter mobile source and tests remain under maintenance, but the release workflow does not build, publish, or advertise Android/iOS downloads.

The stable update manifest location is:

```text
https://github.com/NnopponS/WheelAthelse/releases/latest/download/latest.json
```

The source-only v1.8.2 release does not publish this manifest. Installed clients
therefore receive no v1.8.2 update offer. When trusted signing is available, the
manifest will contain only the signed Windows installer. The client accepts an
installer only when its HTTPS URL belongs to this repository's GitHub Releases
path and its exact byte size and SHA-256 match the manifest.

## Required signing configuration

Public release jobs require a trusted Windows code-signing PFX and RFC3161 timestamp URL:

```text
GitHub secret: WHEELATHLETE_SIGN_PFX_BASE64
GitHub secret: WHEELATHLETE_SIGN_PFX_PASSWORD
GitHub variable: WHEELATHLETE_TIMESTAMP_URL
```

The workflow imports the certificate into the current user's store, builds the package, and signs/verifies the GUI, acquisition daemon, and installer. Missing or invalid signing material fails the Windows job. Never commit the PFX, password, certificate thumbprint, or private key.

Microsoft download reputation warnings and Application Control error 4551 are separate trust decisions. Checksums protect integrity after download; they do not establish publisher trust. Do not publish or describe an unsigned build as fixing either warning.

## Release gates

Before creating `v1.8.2`:

1. Run project and staged hygiene checks.
2. Run the complete Windows suite and the retained mobile maintenance suite.
3. Build changed firmware and complete the physical center and L/R/C acceptance recorded in `.project/STATUS.md`.
4. Build a signed Windows package and confirm every entry in `signing-report.json` is `Valid`.
5. Test download, install, GUI/daemon launch, upgrade, uninstall, and reinstall on Windows. Confirm installation-owned binaries, processes, shortcuts, and registration are removed while recordings and custom models survive.
6. Import the synthetic portable model bundle in a clean installed app and confirm invalid bundles are rejected.
7. Review the final diff and release contents for recordings, private paths, credentials, and generated research data.

If signing or hardware acceptance is still open, do not publish binaries or an
update manifest. A source-only Release page may be published when requested, but
its notes must state the open gates accurately.

## Planned signed assets

```text
WheelAthleteSetup-1.8.2.exe
WheelAthlete-1.8.2-portable.zip
SHA256SUMS.txt
signing-report.json
latest.json
```

The v1.8.2 GitHub page currently contains GitHub's automatic source archives
only. The GitHub workflow tests source, imports signing material, builds the
Windows outputs, verifies signatures, generates `latest.json`, and publishes the
listed assets only after signing succeeds. The source branch was merged to
`main` without force-pushing before the release tag was created.

See [RELEASE_NOTES_1.8.2.md](RELEASE_NOTES_1.8.2.md) for the prepared release notes and `applications/wheelathlete_windows/packaging/windows/README.md` for local build and uninstall details.
