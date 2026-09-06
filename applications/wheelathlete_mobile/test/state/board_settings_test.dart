import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/ble/ble_repository.dart';
import 'package:wheelathlete/ble/control_command.dart';
import 'package:wheelathlete/ble/device_info.dart';
import 'package:wheelathlete/ble/wheel_id.dart';
import 'package:wheelathlete/state/ble_providers.dart';
import 'package:wheelathlete/state/board_settings_providers.dart';
import 'package:wheelathlete/theme/theme.dart';

const _leftInfo = DeviceInfo(
  wheelId: WheelId.left,
  fwMajor: 1,
  fwMinor: 0,
  fwPatch: 0,
  accelRange: 0,
  gyroRange: 3,
  accelScale: 1 / 16384,
  gyroScale: 1 / 16.4,
);

List<int> _configBytes({
  String name = 'WheelAthlete-L',
  int wheelByte = 0x4C,
  int rateHz = 100,
}) {
  final bytes = List<int>.filled(22, 0);
  final nameBytes = name.codeUnits;
  for (var i = 0; i < nameBytes.length && i < 16; i++) {
    bytes[i] = nameBytes[i] & 0xFF;
  }
  bytes[16] = wheelByte;
  final b = ByteData(2)..setUint16(0, rateHz, Endian.little);
  bytes[17] = b.getUint8(0);
  bytes[18] = b.getUint8(1);
  bytes[19] = 1;
  bytes[20] = 1;
  bytes[21] = 0;
  return bytes;
}

void main() {
  late FakeBleRepository ble;
  late ProviderContainer container;

  setUp(() async {
    ble = FakeBleRepository(
      devices: [const FakeDevice(id: 'L1', name: 'WheelAthlete-L', rssi: -42)],
      infoFor: const {'L1': _leftInfo},
      configFor: {'L1': _configBytes()},
    );
    container = ProviderContainer(
      overrides: [
        bleRepositoryProvider.overrideWith((ref) => ble),
        rssiPollIntervalProvider.overrideWith((ref) => null),
        interConnectSettleDelayProvider.overrideWith((ref) => Duration.zero),
      ],
    );
    addTearDown(container.dispose);
    await container.read(connectionManagerProvider.notifier).connect('L1');
  });

  test('readConfig returns parsed BoardConfig', () async {
    final config = await ble.readConfig('L1');
    expect(config.name, 'WheelAthlete-L');
    expect(config.wheelId, WheelId.left);
    expect(config.rateHz, 100);
  });

  test('BoardSettingsNotifier loads config on build', () async {
    // Read the provider — triggers build which schedules _loadConfig.
    container.read(boardSettingsProvider(WheelSide.left));
    // Allow the delayed Future to run.
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final state = container.read(boardSettingsProvider(WheelSide.left));
    expect(state.status, BoardSettingsStatus.loaded);
    expect(state.config, isNotNull);
    expect(state.config!.name, 'WheelAthlete-L');
    expect(state.config!.rateHz, 100);
  });

  test(
    'BoardSettingsNotifier.save writes name, wheel, rate, and sound setting',
    () async {
      // Load config first.
      container.read(boardSettingsProvider(WheelSide.left));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final notifier = container.read(
        boardSettingsProvider(WheelSide.left).notifier,
      );
      await notifier.save(
        name: 'NewName',
        wheelByte: 0x52,
        rateHz: 200,
        beepEnabled: false,
      );
      final state = container.read(boardSettingsProvider(WheelSide.left));
      expect(state.status, BoardSettingsStatus.saved);

      // Verify all four commands were written in order.
      final writes = ble.allControlWrites('L1');
      expect(writes.length, 4);
      expect(writes[0][0], ControlCommandId.setName);
      expect(writes[1][0], ControlCommandId.setWheel);
      expect(writes[2][0], ControlCommandId.setRate);
      expect(writes[3], [ControlCommandId.setBeepEnabled, 0]);
    },
  );

  test('BoardSettingsNotifier.save re-reads config after save', () async {
    // Load config first.
    container.read(boardSettingsProvider(WheelSide.left));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final notifier = container.read(
      boardSettingsProvider(WheelSide.left).notifier,
    );
    await notifier.save(
      name: 'NewName',
      wheelByte: 0x52,
      rateHz: 200,
      beepEnabled: true,
    );
    final state = container.read(boardSettingsProvider(WheelSide.left));
    expect(state.status, BoardSettingsStatus.saved);
    // Config should be re-read (not null) after save.
    expect(state.config, isNotNull);
  });

  test(
    'BoardSettingsNotifier.save with disconnected wheel sets error',
    () async {
      // Use a fresh container with no connection on right side.
      final notifier = container.read(
        boardSettingsProvider(WheelSide.right).notifier,
      );
      await notifier.save(
        name: 'Test',
        wheelByte: 0x52,
        rateHz: 100,
        beepEnabled: true,
      );
      final state = container.read(boardSettingsProvider(WheelSide.right));
      expect(state.status, BoardSettingsStatus.error);
      expect(state.error, isNotNull);
    },
  );

  test('readConfig throws if no config seeded', () async {
    final bleNoConfig = FakeBleRepository(
      devices: [const FakeDevice(id: 'X1', name: 'X', rssi: -40)],
      infoFor: const {'X1': _leftInfo},
    );
    final c = ProviderContainer(
      overrides: [
        bleRepositoryProvider.overrideWith((ref) => bleNoConfig),
        rssiPollIntervalProvider.overrideWith((ref) => null),
        interConnectSettleDelayProvider.overrideWith((ref) => Duration.zero),
      ],
    );
    addTearDown(c.dispose);
    await c.read(connectionManagerProvider.notifier).connect('X1');
    expect(() => bleNoConfig.readConfig('X1'), throwsStateError);
  });
}
