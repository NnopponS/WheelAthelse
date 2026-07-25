from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_xiao_batches_for_slow_dual_board_links_and_backs_off_retries():
    types = (ROOT / "src" / "ble_types.h").read_text(encoding="utf-8")
    header = (ROOT / "src" / "ble_service.h").read_text(encoding="utf-8")
    source = (ROOT / "src" / "ble_service.cpp").read_text(encoding="utf-8")

    assert "TARGET_NOTIFICATIONS_PER_SECOND = 10" in types
    assert "notificationRetryDelayMs" in types
    assert "BATCH_MAX_LATENCY_MS = 100" in header
    assert "retry_after_ms_" in header
    assert "notificationRetryDue" in source
    assert "consecutive_transport_failures_" in source


def test_xiao_stop_drains_late_samples_before_final_health():
    header = (ROOT / "src" / "ble_service.h").read_text(encoding="utf-8")
    source = (ROOT / "src" / "ble_service.cpp").read_text(encoding="utf-8")

    handle_stop = source[
        source.index("void BleService::handleStop()") :
        source.index("void BleService::handleSetRate")
    ]
    finalize = source[
        source.index("void BleService::finalizeStopIfDrained()") :
        source.index("bool BleService::notifyPendingBatch()")
    ]

    assert "stop_finalization_pending_" in header
    assert "STOP_DRAIN_QUIET_MS" in header
    assert "stop_finalization_pending_ = true" in handle_stop
    assert "sendAcqHealth()" not in handle_stop
    assert "flushBatch()" in finalize
    assert "imu().queueDepth() != 0" in finalize
    assert "pending_count_ != 0" in finalize
    assert finalize.index("sendAcqHealth()") < finalize.index("sendStopFired(")
