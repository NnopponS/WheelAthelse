import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('app, firmware, and protocol release versions stay synchronized', () {
    final app = File('pubspec.yaml').readAsStringSync();
    final m5 = File('../M5plus2_firmware/platformio.ini').readAsStringSync();
    final xiao = File('../Xiao_firmware/platformio.ini').readAsStringSync();
    final protocol = File('../docs/ble-protocol.md').readAsStringSync();
    final readme = File('../README.md').readAsStringSync();

    expect(app, contains('version: 1.7.0+8'));
    for (final firmware in [m5, xiao]) {
      expect(firmware, contains('WheelAthlete_FW_MAJOR=1'));
      expect(firmware, contains('WheelAthlete_FW_MINOR=7'));
      expect(firmware, contains('WheelAthlete_FW_PATCH=0'));
    }
    expect(protocol, contains('`1.7.0`'));
    expect(readme, contains('App version 1.7.0+8'));
    expect(readme, contains('Firmware version 1.7.0'));
  });
}
