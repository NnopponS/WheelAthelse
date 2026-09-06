# WheelAthlete â€” Current Progress

Updated: 2026-09-06 (Asia/Bangkok)

Branch: `codex/pc-version`

## Current product state

WheelAthlete has exactly two maintained operator applications:

1. **WheelAthlete Mobile Application** â€” `applications/wheelathlete_mobile/` â€” Flutter, iOS + Android.
2. **WheelAthlete Windows Research Application** â€” `applications/wheelathlete_windows/` â€” Python, PySide6 GUI + separate acquisition daemon.

Maintained firmware lives only under `hardware_firmware/`:

- `hardware_firmware/m5stickc_plus2/`
- `hardware_firmware/xiao_nrf52840_sense/`

Current coordinated release: product/Windows/firmware/BLE protocol `1.8.0`, mobile `1.8.0+10`.

## Formal repository organization â€” 2026-09-06

Completed:

- introduced top-level `applications/` and `hardware_firmware/` product domains;
- renamed the maintained app directories to `wheelathlete_mobile/` and `wheelathlete_windows/`;
- renamed firmware directories to `m5stickc_plus2/` and `xiao_nrf52840_sense/`;
- renamed the Windows source launcher to `run_wheelathlete_windows.bat`;
- renamed the Windows GUI log to `wheelathlete-windows.log`;
- updated Windows packaging root discovery for the additional `applications/` hierarchy;
- updated MODEL repository-root resolution for the new hierarchy;
- rebuilt `.gitignore` around the formal paths;
- added `applications/README.md` and `hardware_firmware/README.md` as directory indexes;
- rewrote the root English and Thai READMEs around the formal product architecture;
- updated tracked documentation and tests so no legacy path names remain;
- removed the empty legacy desktop application directory after migration.

## Maintained capabilities

### Mobile

- direct dual-wheel BLE acquisition;
- realtime IMU preview;
- clock synchronization and synchronized recording;
- topic/trial/session organization;
- templates, experiment tracking, tags, search/filter;
- session preview, QC/statistics;
- CSV/Excel/ZIP export;
- Android + iOS only.

### Windows

- acquisition daemon owns BLE and authoritative raw-data path;
- append-only `.waj` journal, recovery, QC and derived CSV;
- PySide6 operator workflow and diagnostics;
- Results metadata editing and export;
- optional offline MODEL trajectory analysis;
- portable EXE and Inno Setup packaging.

### Firmware / protocol

- M5StickC Plus2 and XIAO nRF52840 Sense targets;
- left/right identity;
- 50/100/200 Hz sampling;
- synchronized lifecycle control;
- sequence/loss telemetry and replay/recovery;
- acquisition-health telemetry;
- BLE protocol `1.8.0`.

## Verification â€” 2026-09-06

Passed after the formal hierarchy migration:

- Flutter coordinated version/path test â€” passed;
- Flutter full test suite â€” passed;
- `flutter analyze` â€” **No issues found**;
- Python PC test suite â€” **67 passed, 1 skipped, 0 warnings**;
- `python -m compileall -q tools/pc_acquisition tools/pc_gui` â€” passed from the Windows app root;
- `run_wheelathlete_windows.bat --help` â€” passed;
- formal layout/packaging path smoke â€” passed;
- legacy path audit â€” zero matches for the former app/firmware directory names;
- `git diff --check` â€” clean.

The skipped Python test is the optional local BiWheel3D checkpoint integration when the untracked model tree is not present.


## Cross-platform application updater â€” 2026-09-06

Completed:

- introduced one stable GitHub Releases manifest for Mobile + Windows at `releases/latest/download/latest.json`;
- added strict schema/channel/version/HTTPS/repository-path validation plus exact size and SHA-256 verification;
- Android release/profile builds can automatically check after startup and every six hours, download a verified APK, and hand installation to Android's system installer;
- Android installation is blocked while Live preview, countdown, or recording is active;
- Android release packaging supports a persistent external keystore and the GitHub release workflow fails closed when signing secrets are missing;
- iOS uses the same release discovery manifest but hands installation to App Store/TestFlight;
- installed Windows PyInstaller/Inno builds can automatically check after startup and every six hours, verify the installer, refuse installation during active acquisition, then relaunch through `/AUTOUPDATE=1`;
- source/demo/portable Windows builds do not self-replace;
- Windows packaging now bundles `VERSION` and explicitly excludes the optional PyTorch/TensorFlow/scientific MODEL stack from the normal installer;
- added `.github/workflows/release.yml` to test/build Android + Windows, generate the exact-artifact manifest, and publish one GitHub Release;
- added `release/` tooling and English/Thai operator/developer documentation;
- public release remains `1.8.0`; Android build advances to `10` so it can replace earlier local `1.8.0+9` APKs while firmware and BLE protocol remain `1.8.0`.

Verification for the updater-enabled application release:

- Flutter updater targeted tests â€” **8 passed**;
- Flutter full test suite â€” **666 passed**;
- `flutter analyze` â€” clean during updater verification;
- Android release APK â€” built successfully as `1.8.0` / `versionCode 10`, final local artifact size **118,649,581 bytes**, SHA-256 `3e1d6e18d5ff64de2203f580ee5874a867c35740987c328f08535f85154c7574`;
- Python Windows full suite â€” **76 passed**;
- Windows updater targeted tests â€” **8 passed**;
- `python -m compileall -q tools/pc_gui tools/pc_acquisition` â€” passed;
- lean Windows PyInstaller + Inno Setup package â€” passed; installer size **44,206,431 bytes**, SHA-256 `85bb01069f657a44186f2a5418c46eb8a33ec1154b5b2a8759fd5173213cd36e`;
- release manifest generator unit test â€” passed;
- release workflow YAML parse â€” passed;
- local manifest generated successfully from the final APK + Windows installer;
- `git diff --check` â€” clean before temporary verification cleanup.

Bootstrap/signing notes:

- public `v1.8.0` is the first updater-enabled release. Earlier local `1.8.0+9` APKs require one manual install of `1.8.0+10`; later releases can use the in-app updater;
- Android in-place updates require the same persistent release signing key and a strictly increasing build number; local debug-signed release APKs are validation artifacts only, not production updater artifacts;
- native iOS packaging still requires macOS/Xcode and a real App Store/TestFlight URL before production iOS update installation can be validated.

## Physical acceptance blocker

Automated tests do not replace physical two-board RF acceptance. Claims about real 0.5/2/5 m packet loss, negotiated controller behavior, and measured left/right start skew remain gated on physical hardware evidence.

### v1.8.0 final release artifacts (2026-09-06)
- Android 1.8.0+10: WheelAthlete-Android-1.8.0.apk, 118649581 bytes, SHA-256 ea247cb88b2257691cff7309716d4f88dd812dbd6015ce6498e82225d133edce; release-signed with the permanent WheelAthlete Android certificate.
- Windows 1.8.0: WheelAthleteSetup-1.8.0.exe, 44210246 bytes, SHA-256 d903cead9bf036b9e86bab5439020a1af51a836ddbc8c4287d0aba0413fa34a8.
- Shared latest.json generated from those exact artifacts and accepted by the Windows updater parser.
- Full Flutter suite: 666 passed; analyzer clean. Full Windows Python suite: 76 passed. M5 and XIAO firmware compile checks passed; XIAO was not flashed or edited.
