from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
XIAO_SRC = ROOT.parent / "xiao_nrf52840_sense" / "src"


def _compact(text: str) -> str:
    return "".join(text.split())


def test_m5_exposes_same_pc_wire_ids_and_packet_contract_as_xiao():
    m5 = (SRC / "ble_types.h").read_text(encoding="utf-8") + (SRC / "config_store.h").read_text(encoding="utf-8")
    xiao = (XIAO_SRC / "ble_types.h").read_text(encoding="utf-8")
    required_tokens = (
        '0000a1b2-0000-1000-8000-00805f9b34fb',
        '0000a1b3-0000-1000-8000-00805f9b34fb',
        '0000a1b4-0000-1000-8000-00805f9b34fb',
        '0000a1b5-0000-1000-8000-00805f9b34fb',
        '0000a1b6-0000-1000-8000-00805f9b34fb',
        '0000a1b7-0000-1000-8000-00805f9b34fb',
        'IMU_SAMPLE_SIZE',
        'SYNC_RESPONSE_SIZE',
        'INFO_SIZE',
        'ACQ_HEALTH_SIZE',
        'ReplayRange= 0x0A',
        'SetBeepEnabled = 0x0B',
        'ResetSeq   = 0xFF',
        'AcqHealth    = 0x60',
        'ReplayResult = 0x61',
        'StartFired   = 0x30',
        'StopFired    = 0x40',
        'CountdownCue= 0x31',
    )
    for token in required_tokens:
        assert token in m5
        assert token in xiao


def test_m5_info_and_config_are_pc_readable_and_identify_m5():
    source = (SRC / "ble_service.cpp").read_text(encoding="utf-8")
    types = (SRC / "ble_types.h").read_text(encoding="utf-8") + (SRC / "config_store.h").read_text(encoding="utf-8")
    assert 'info_buf[14] = 1' in source
    assert 'info_buf[15] = 0x01' in source
    assert 'packInfo(' in source
    assert 'packConfig(' in source
    assert 'CONFIG_SIZE' in types
    assert 'CHAR_CONFIG_UUID' in types


def test_pc_connect_forces_clean_idle_sequence_epoch_like_xiao():
    source = (SRC / "ble_service.cpp").read_text(encoding="utf-8")
    header = (SRC / "imu_reader.h").read_text(encoding="utf-8")
    connect = source[source.index('void BleService::onConnect'):source.index('void BleService::onDisconnect')]
    assert 'resetQueueAndSeq()' in header
    assert 'if (imu().running())' in connect
    assert 'imu().stop()' in connect
    assert 'imu().resetQueueAndSeq()' in connect
    assert connect.index('imu().stop()') < connect.index('imu().resetQueueAndSeq()')


def test_start_resets_epoch_before_waiting_for_scheduled_t0():
    source = (SRC / "ble_service.cpp").read_text(encoding="utf-8")
    start = source[source.index('void BleService::handleStart'):source.index('void BleService::handleStop')]
    assert 'if (imu().running())' in start
    assert 'imu().stop()' in start
    assert 'imu().resetQueueAndSeq()' in start
    assert start.index('imu().stop()') < start.index('imu().resetQueueAndSeq()')
    assert start.index('imu().resetQueueAndSeq()') < start.index('target_start_us_ = target_start_us')


def test_connected_pc_owns_start_stop_and_rate_controls():
    source = (SRC / "main.cpp").read_text(encoding="utf-8")
    compact = _compact(source)
    assert 'if(!ble().connected()&&M5.BtnA.wasPressed())' in compact
    assert 'if(!ble().connected()&&M5.BtnB.wasPressed())' in compact


def test_m5_sync_and_stop_contract_matches_pc_expectations():
    source = (SRC / "ble_service.cpp").read_text(encoding="utf-8")
    assert 'packSyncResponse(' in source
    assert 'sendStartFired()' in source
    assert 'sendAcqHealth()' in source
    assert 'sendStopFired(stop_device_us_)' in source
    finalize = source[source.index('void BleService::finalizeStopIfDrained'):source.index('bool BleService::notifyPendingBatch')]
    assert finalize.index('sendAcqHealth()') < finalize.index('sendStopFired(stop_device_us_)')


def test_m5_replay_capability_is_real_not_only_advertised():
    source = (SRC / "ble_service.cpp").read_text(encoding="utf-8")
    assert 'handleReplayRange(' in source
    assert 'replay_history_' in source
    assert 'packReplayResult(' in source
    assert 'replay_pending_ = false' in source
