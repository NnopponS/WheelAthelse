from pathlib import Path


ROOT = Path(__file__).parents[1]
MAIN = ROOT / "src" / "main.cpp"


def test_m5_has_exactly_one_ble_streaming_owner():
    source = MAIN.read_text(encoding="utf-8")
    owner = source[
        source.index("static void bleStreamingTask") : source.index("void setup()")
    ]

    assert source.count("ble().bleTask();") == 1, (
        "BLE batching must have one owner; concurrent calls race pending_count_, "
        "batch buffers, replay history, and notify()"
    )
    assert "xTaskCreatePinnedToCore(bleStreamingTask" in source, (
        "The sole BLE owner must be started; a dormant task definition leaves "
        "the IMU queue with no consumer"
    )
    assert source.count("ble().tick();") == 1
    assert "ble().tick();" in owner, (
        "scheduled starts, battery, and sync/drop GATT notifications must share "
        "the same serialized BLE owner as live IMU notifications"
    )


def test_m5_display_uses_cached_battery_during_acquisition():
    source = MAIN.read_text(encoding="utf-8")

    assert "M5.Power.getBatteryLevel()" not in source
    assert "ble().batteryLevel()" in source


def test_m5_display_refresh_never_clears_background_regions():
    source = (ROOT / "src" / "display.cpp").read_text(encoding="utf-8")
    refresh = source[
        source.index("void StatusDisplay::refresh") :
        source.index("void StatusDisplay::showCountdown")
    ]
    begin = source[
        source.index("void StatusDisplay::begin") :
        source.index("void StatusDisplay::refresh")
    ]

    assert "fillScreen(BLACK)" in begin
    assert "fillScreen" not in refresh
    assert "fillRect" not in refresh, (
        "The refresh loop may update changed glyphs only; clearing rectangles "
        "causes visible black flicker on the M5 LCD"
    )


def test_m5_control_commands_are_serialized_by_the_ble_owner():
    source = (ROOT / "src" / "ble_service.cpp").read_text(encoding="utf-8")
    callback = source[
        source.index("void BleService::onControlWrite") :
        source.index("// ── Command handlers")
    ]

    assert "xQueueCreate" in source
    assert "xQueueSend" in callback
    assert "handleCommand" not in callback
    assert "xQueueReceive" in source[source.index("void BleService::bleTask()") :]


def test_m5_retains_pending_batch_when_notify_fails():
    source = (ROOT / "src" / "ble_service.cpp").read_text(encoding="utf-8")
    notify = source[
        source.index("bool BleService::notifyPendingBatch()") :
        source.index("void BleService::flushBatch()")
    ]

    assert "if (notifyImuBatch(batch_buf_, len))" in notify
    assert notify.index("if (notifyImuBatch(batch_buf_, len))") < notify.index(
        "pending_count_ = 0"
    )

    replay = source[
        source.index("if (service_replay)") :
        source.index("if (!imu().running())")
    ]
    assert "if (notifyImuBatch(batch_buf_, len))" in replay
    assert replay.index("if (notifyImuBatch(batch_buf_, len))") < replay.index(
        "replay_sent_ += found"
    )

    host_notify = source[
        source.index("bool BleService::notifyImuBatch") :
        source.index("void BleService::flushBatch()")
    ]
    assert "ble_gatts_notify_custom" in host_notify
    assert "++transport_failures_" in host_notify


def test_m5_interleaves_replay_with_live_batches():
    header = (ROOT / "src" / "ble_service.h").read_text(encoding="utf-8")
    source = (ROOT / "src" / "ble_service.cpp").read_text(encoding="utf-8")

    assert "replay_turn_" in header
    assert "const bool service_replay" in source
    assert "replay_turn_ = !replay_turn_" in source
