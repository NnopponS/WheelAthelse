from pathlib import Path


SRC = Path(__file__).parents[1] / "src"


def test_peripheral_requests_10_ms_interval_and_247_mtu():
    source = (SRC / "ble_service.cpp").read_text()
    compact = "".join(source.split())
    assert "PREFERRED_CONN_INTERVAL_UNITS = 8" in source
    assert "requestConnectionParameter(PREFERRED_CONN_INTERVAL_UNITS,0," in compact
    assert "requestMtuExchange(247)" in source


def test_link_log_uses_the_negotiated_values():
    source = (SRC / "ble_service.cpp").read_text()
    assert "getMtu()" in source
    assert "getConnectionInterval()" in source
    assert "[BLE] Link MTU=" in source


def test_imu_sample_is_one_burst_with_midpoint_timestamp():
    source = (SRC / "imu_reader.cpp").read_text()
    compact = "".join(source.split())
    assert "readRegisterRegion(raw,LSM6DS3_ACC_GYRO_OUTX_L_G,sizeof(raw))" in compact
    assert "read_started_us + ((read_finished_us - read_started_us) / 2)" in source
    assert "readRawAccelX()" not in source
    assert "readRawGyroX()" not in source
    assert "CTRL3_C_BDU_IF_INC = 0x44" in source
