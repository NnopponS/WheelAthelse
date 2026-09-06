# Testing

Current release line: `v1.8.0`.

WheelAthlete separates pure logic from hardware/UI boundaries so most correctness can be tested without physical sensors. Physical BLE behavior remains a separate acceptance gate.

## Flutter mobile

```bash
cd applications/wheelathlete_mobile
flutter test
flutter analyze
```

Coverage includes BLE parsing, synchronization, recording/storage state, session metadata, preview/statistics, export, and widget/UI behavior. Real `flutter_blue_plus` radio behavior still requires a physical phone + sensor boards.

## Python Windows stack

From repository root:

```bash
python -m pytest applications/wheelathlete_windows/tools/pc_acquisition/tests applications/wheelathlete_windows/tools/pc_gui/tests -q
python -m compileall -q applications/wheelathlete_windows/tools/pc_acquisition applications/wheelathlete_windows/tools/pc_gui
```

The acquisition suite covers strict parsing, lifecycle, journal/QC/recovery, IPC, queue/backpressure behavior, acceptance evaluation, and fault cases. GUI tests cover state mapping, IPC handling, experiment persistence, and offscreen smoke workflows.

## Firmware

### M5StickCPlus2

```bash
cd hardware_firmware/m5stickc_plus2
python -m pytest test -q
pio test -e native
```

### XIAO nRF52840 Sense

```bash
cd hardware_firmware/xiao_nrf52840_sense
python -m pytest test -q
```

PlatformIO target builds are additional firmware gates where the local toolchain is available.

## Version consistency

`applications/wheelathlete_mobile/test/version_consistency_test.dart` checks the coordinated release declarations across:

- root `VERSION`;
- Flutter mobile version;
- both firmware targets;
- BLE protocol;
- root README;
- Windows packaging scripts.

## Packaging

`applications/wheelathlete_windows/packaging/windows/build_installer.bat` is the supported Windows packaging path. A successful package build produces a PyInstaller GUI distribution with the daemon bundled, a portable ZIP, and an Inno Setup installer.

## Physical acceptance

Automated tests and long-run simulations do **not** prove RF performance. Real claims about 0.5/2/5 m behavior, actual dual-wheel equality, negotiated controller behavior, or physical start skew require the prepared two-XIAO hardware acceptance matrix.

Verification evidence and historical test reports are stored in `docs/testing/`.
