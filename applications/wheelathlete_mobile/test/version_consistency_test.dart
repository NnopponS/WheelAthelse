import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('coordinated release versions stay synchronized', () {
    final repoRoot = Directory.current.parent.parent.path;
    final productVersion = File('$repoRoot/VERSION').readAsStringSync().trim();
    final app = File('pubspec.yaml').readAsStringSync();
    final sessionModel = File(
      'lib/records/session_model.dart',
    ).readAsStringSync();
    final exportActions = File(
      'lib/export/export_actions.dart',
    ).readAsStringSync();
    final m5 = File(
      '$repoRoot/hardware_firmware/m5stickc_plus2/platformio.ini',
    ).readAsStringSync();
    final xiao = File(
      '$repoRoot/hardware_firmware/xiao_nrf52840_sense/platformio.ini',
    ).readAsStringSync();
    final protocol = File('$repoRoot/docs/ble-protocol.md').readAsStringSync();
    final readme = File('$repoRoot/README.md').readAsStringSync();
    final buildScript = File(
      '$repoRoot/applications/wheelathlete_windows/packaging/windows/build_installer.bat',
    ).readAsStringSync();
    final installer = File(
      '$repoRoot/applications/wheelathlete_windows/packaging/windows/installer.iss',
    ).readAsStringSync();
    final appVersion = File('lib/update/app_version.dart').readAsStringSync();
    final updateService = File(
      'lib/update/mobile_update_service.dart',
    ).readAsStringSync();
    final releaseWorkflow = File(
      '$repoRoot/.github/workflows/release.yml',
    ).readAsStringSync();

    expect(productVersion, '1.8.0');
    expect(app, contains('version: 1.8.0+10'));
    expect(sessionModel, contains("this.protocolVersion = '1.8.0'"));
    expect(
      exportActions,
      contains(
        "'app_version': '\$wheelAthleteAppVersion+\$wheelAthleteAppBuild'",
      ),
    );
    expect(exportActions, contains("'firmware_version': '1.8.0'"));
    expect(exportActions, contains("'protocol_version': '1.8.0'"));
    for (final firmware in [m5, xiao]) {
      expect(firmware, contains('WheelAthlete_FW_MAJOR=1'));
      expect(firmware, contains('WheelAthlete_FW_MINOR=8'));
      expect(firmware, contains('WheelAthlete_FW_PATCH=0'));
    }
    expect(protocol, contains('1.8.0'));
    expect(readme, contains('**Current release line:** `v1.8.0`'));
    expect(readme, contains('applications/wheelathlete_mobile/'));
    expect(readme, contains('applications/wheelathlete_windows/'));
    expect(readme, contains('hardware_firmware/m5stickc_plus2/'));
    expect(readme, contains('hardware_firmware/xiao_nrf52840_sense/'));
    expect(buildScript, contains(r'set /p APP_VERSION=<"%REPO_ROOT%\VERSION"'));
    expect(installer, contains('#define MyAppVersion "1.8.0"'));
    expect(installer, contains(r'#define WindowsAppRoot "..\.."'));
    expect(appVersion, contains("wheelAthleteAppVersion = '1.8.0'"));
    expect(appVersion, contains('wheelAthleteAppBuild = 10'));
    expect(appVersion, contains('releases/latest/download/latest.json'));
    expect(updateService, contains('wheelathlete/app_update'));
    expect(releaseWorkflow, contains('workflow_dispatch:'));
    expect(releaseWorkflow, contains('generate_update_manifest.py'));
  });
}
