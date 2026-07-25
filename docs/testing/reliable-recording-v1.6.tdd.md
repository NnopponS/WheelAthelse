# WheelAthlete 1.6 reliable recording verification

Date: 2026-07-21

## Versions

- App: `1.6.0+6`
- Firmware: `1.6.0`
- BLE protocol: `1.6.0`
- Session schema: `4`
- Export schema: `2`

## Automated gates

| Gate | Result |
|---|---|
| `flutter test --concurrency=1` | PASS, 626 tests |
| `dart analyze lib` | PASS, no issues |
| `flutter build apk --release` | PASS |
| APK manifest/signature | PASS, `com.wheelathlete.wheelathlete` v1.6.0 (6), APK v2 verified |
| M5 Python host tests | PASS, 132 tests |
| XIAO Python host tests | PASS, 11 tests |
| M5 PlatformIO left/right | PASS, both release images |
| XIAO PlatformIO left/right | PASS, both DFU packages |
| Dataset processor tests | PASS, 5 tests |
| July generated-output validation | PASS, 38 stable files checked |
| M5 left flash (`COM4`) | PASS, MAC `00:4B:12:C4:CB:30` |
| M5 right flash (`COM15`) | PASS, MAC `C0:CD:D6:14:96:DC` |
| Physical dual-board Start/Stop | PASS, 20 consecutive 100 Hz cycles with no zero-sample trial |
| Physical first-sample latency | PASS, worst case 250 ms across 40 wheel starts |
| Physical acquisition health | PASS, every cycle produced=notified=received; 0 drops/failures/depth |

PlatformIO's optional M5 `native` Unity runner could not execute because this
Windows host has no `gcc` or `g++` executable. The pure host contract suite and
the real ESP32 cross-builds both pass.

## July dataset result

Output: `C:\Users\worap\Desktop\Data_WheelAthlete\20260710_processed_v2`

- Ready: 1
- Degraded: 3
- IMU only: 1 (`one_stroke trial_01`, missing C3D)
- Unmatched: 1 (`T101.c3d`)
- Rejected: 4
- Raw CSVs: 18
- Aligned training CSVs: 9
- QC JSON files: 11, including the validation report

Only `anti_clock_wise trial_01` is marked `ready_to_train=True`. The manifest
keeps every other trial out of the default training set while preserving its
raw and diagnostic outputs.

## Release artifacts and SHA-256

| Artifact | SHA-256 |
|---|---|
| `app/build/app/outputs/flutter-apk/app-release.apk` | `F1025DAA2C15D70F5EFF8A9B41DDCE14216B922ECF4FCCF08F6830E88A8E1CD5` |
| `M5plus2_firmware/.pio/build/left/firmware.bin` | `435FFADBC9B0B246FB83F48489F32F531DA5ECAE03299EE8D3F9D094C84103F0` |
| `M5plus2_firmware/.pio/build/right/firmware.bin` | `8D2870C2955A893305557E63BC07AFCF433586201A435A2AAD9F6D18F23A455F` |
| `Xiao_firmware/.pio/build/left/firmware.zip` | `EE3841B0972291CA5D3F5193354BDE51EB608A41C9F616F1586E37D6807A783C` |
| `Xiao_firmware/.pio/build/right/firmware.zip` | `3F01C41ED1FF73A488B4BB5ED9277101489D2022CAAEC6E2D1A5FA4537830BFE` |
| `Xiao_firmware/.pio/build/left/firmware.hex` | `65164D507425D310DBA58E66FC0F534C7C3063983546E43381B22825279555BC` |
| `Xiao_firmware/.pio/build/right/firmware.hex` | `08A18D18042CAEB365B5AF68043E0D7A6BF993790FA7B8F75BF53D117A4C750C` |
| July `dataset_manifest.csv` | `BB34E60849E2EBE7F33598CF71AB90A09DEA2EC3DD4968A29B084A895D24C84B` |
| July `qc/validation_report.json` | `B29D5E6F93EBC1D5EB00743782EAEC30CE82D146197917886353F0305DC5EE4E` |

## External release gates still required

Both M5 boards were attached, flashed, boot-verified, and exercised together
through BLE. The current final images passed 20 consecutive dual-wheel 100 Hz
Start/Stop cycles, exact final count matching, continuous sequences, and zero
acquisition-health errors. No Android ADB device is attached, so installation
and target-phone profile/jank measurement remain external gates. The sustained
10-minute 100 Hz test was stopped at the user's request, and 200 Hz validation
was intentionally deferred because the current workflow uses 100 Hz.
The repository does not contain a user-owned Android release keystore; the
generated release-mode APK is currently signed with the Android debug
certificate and must be re-signed with the project release key before public
store distribution.

## Added regression evidence

- RED: immediate first-packet test reproduced the zero-sample race; GREEN after
  attaching the lossless recorder before presentation streams and resetting
  notification CCCDs on every physical reconnect.
- RED: the presentation interval test observed 250 ms; GREEN at 33 ms (30 Hz).
- RED: display structural test found `fillRect` in the refresh loop; GREEN with
  all full-screen/background fills confined to `begin()` and changed-glyph-only
  updates in `refresh()`.
- RED: v1.6 config/command tests failed before `beep_enabled` and command `0x0B`;
  GREEN for Flutter, M5, and XIAO with legacy 22/30-byte app compatibility.
- RED: both firmware targets exposed a stale marker CSV header; GREEN after
  removing that diagnostic header, leaving the app's schema-2 raw/training CSVs
  as the only user-facing data contracts.
- RED: a simultaneous dual-board run reproduced the reported failure as a
  saturated second-board queue (`Q=256`, increasing drops and transport
  failures); GREEN after reducing notification pressure to about 10 batched
  notifications per second, requesting a 7.5-15 ms connection interval, and
  replacing the 1 ms retry storm with bounded 10-100 ms backoff.
- RED: cycle 2 of the first 20-cycle physical gate reported one final sample
  still queued (`produced=83`, `notified=82`, depth 1); GREEN after STOP gained
  a 30 ms quiet-drain finalization phase. The rerun passed all 20 cycles with a
  worst first-sample latency of 250 ms and exact final counts on both wheels.
