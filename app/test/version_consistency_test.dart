import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('coordinated release versions stay synchronized', () {
    final productVersion = File('../VERSION').readAsStringSync().trim();
    final app = File('pubspec.yaml').readAsStringSync();
    final sessionModel =
        File('lib/records/session_model.dart').readAsStringSync();
    final exportActions =
        File('lib/export/export_actions.dart').readAsStringSync();
    final m5 = File('../M5plus2_firmware/platformio.ini').readAsStringSync();
    final xiao = File('../Xiao_firmware/platformio.ini').readAsStringSync();
    final protocol = File('../docs/ble-protocol.md').readAsStringSync();
    final readme = File('../README.md').readAsStringSync();
    final buildScript =
        File('../packaging/windows/build_installer.bat').readAsStringSync();
    final installer =
        File('../packaging/windows/installer.iss').readAsStringSync();

    expect(productVersion, '1.8.0');
    expect(app, contains('version: 1.8.0+9'));
    expect(sessionModel, contains("this.protocolVersion = '1.8.0'"));
    expect(exportActions, contains("'app_version': '1.8.0+9'"));
    expect(exportActions, contains("'firmware_version': '1.8.0'"));
    expect(exportActions, contains("'protocol_version': '1.8.0'"));
    for (final firmware in [m5, xiao]) {
      expect(firmware, contains('WheelAthlete_FW_MAJOR=1'));
      expect(firmware, contains('WheelAthlete_FW_MINOR=8'));
      expect(firmware, contains('WheelAthlete_FW_PATCH=0'));
    }
    expect(protocol, contains('เวอร์ชัน: `1.8.0`'));
    expect(readme, contains('**Current release line:** `v1.8.0`'));
    expect(readme, contains('Flutter mobile | `1.8.0+9`'));
    expect(readme, contains('Python Windows installer | `1.8.0`'));
    expect(buildScript, contains('set /p APP_VERSION=<VERSION'));
    expect(installer, contains('#define MyAppVersion "1.8.0"'));
  });
}
