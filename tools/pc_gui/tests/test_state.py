from tools.pc_gui.state import AppViewState, BoardView, PreviewBuffer, PreviewSample


def _preview(seq: int) -> PreviewSample:
    return PreviewSample(
        side="L",
        seq=seq,
        device_us=seq * 10_000,
        pc_ns=seq * 10_000_000,
        ax=1,
        ay=2,
        az=3,
        gx=4,
        gy=5,
        gz=6,
    )


def test_preview_buffer_is_bounded_and_keeps_latest_sample():
    buffer = PreviewBuffer(maxlen=3)
    for seq in range(5):
        buffer.append(_preview(seq))
    assert [sample.seq for sample in buffer.values()] == [2, 3, 4]
    assert buffer.latest().seq == 4


def test_board_view_maps_host_firmware_and_sync_metrics():
    board = BoardView.from_status(
        "L",
        {
            "connected": True,
            "device_id": "left",
            "mtu": 247,
            "samples": 1234,
            "notifications": 124,
            "samples_hz": 100.02,
            "notifications_hz": 10.01,
            "sequence_gaps": 0,
            "queue_high_water": 7,
            "info": {
                "name": "WheelAthlete-L",
                "firmware": "1.8.0",
                "battery_percent": 91,
                "rssi": -47,
                "sample_rate_hz": 100,
                "accel_range": 1,
                "gyro_range": 3,
                "accel_scale": 0.0001220703125,
                "gyro_scale": 0.06103515625,
            },
            "health": {
                "produced": 1234,
                "notified": 1234,
                "queue_drops": 0,
                "transport_failures": 0,
                "queue_depth": 0,
                "fifo_faults": 0,
                "fifo_dropped_samples": 0,
            },
            "clock": {
                "best_rtt_ns": 1_500_000,
                "median_rtt_ns": 2_000_000,
                "drift_ppm": 3.25,
                "residual_rms_ns": 125_000,
            },
        },
    )
    assert board.connected
    assert board.name == "WheelAthlete-L"
    assert board.mtu == 247
    assert board.samples_hz == 100.02
    assert board.accel_range == 1
    assert board.gyro_range == 3
    assert board.produced == board.notified == 1234
    assert board.best_rtt_ms == 1.5
    assert board.residual_rms_ms == 0.125
    assert board.healthy


def test_app_state_preserves_both_wheels_and_ipc_counters():
    state = AppViewState()
    state.apply_status(
        {
            "recording": True,
            "live": True,
            "live_sides": ["L"],
            "session_id": "abc",
            "journal_root": "C:/sessions",
            "incomplete_sessions": ["broken.open"],
            "boards": {
                "L": {"connected": True, "info": {"name": "L"}},
                "R": {"connected": False},
            },
            "ipc": {"preview_events_dropped": 2},
        }
    )
    assert state.recording
    assert state.live
    assert state.live_sides == ("L",)
    assert state.session_id == "abc"
    assert state.connected_sides() == ("L",)
    assert state.incomplete_sessions == ("broken.open",)
    assert state.ipc["preview_events_dropped"] == 2
