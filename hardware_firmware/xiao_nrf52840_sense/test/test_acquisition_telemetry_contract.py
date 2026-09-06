from pathlib import Path


SOURCE = Path(__file__).parents[1] / "src" / "ble_service.cpp"


def test_xiao_skips_blocking_battery_adc_work_while_acquiring():
    source = SOURCE.read_text(encoding="utf-8")
    body = source[
        source.index("void BleService::updateBatteryLevel()") :
        source.index("void BleService::onConnect")
    ]

    guard = body.index("if (imu().running())")
    adc_loop = body.index("for (uint8_t i = 0; i < 5; ++i)")
    assert guard < adc_loop


def test_xiao_interleaves_replay_with_live_batches():
    header = (SOURCE.parent / "ble_service.h").read_text(encoding="utf-8")
    source = SOURCE.read_text(encoding="utf-8")

    assert "replay_turn_" in header
    assert "const bool service_replay" in source
    assert "replay_turn_ = !replay_turn_" in source
