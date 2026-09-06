from pathlib import Path


ROOT = Path(__file__).parents[1]


def test_m5_exposes_persistent_countdown_sound_config():
    config = (ROOT / "src" / "config_store.h").read_text(encoding="utf-8")
    commands = (ROOT / "src" / "ble_types.h").read_text(encoding="utf-8")
    service = (ROOT / "src" / "ble_service.cpp").read_text(encoding="utf-8")

    assert "CONFIG_SIZE   = 31" in config
    assert "buf[30]" in config
    assert "beepEnabled" in config
    assert "SetBeepEnabled" in commands
    assert "handleSetBeepEnabled" in service
    assert "configStore().beepEnabled()" in service


def test_m5_visual_countdown_remains_active_when_sound_is_disabled():
    service = (ROOT / "src" / "ble_service.cpp").read_text(encoding="utf-8")
    countdown = service[service.index("const int8_t beep_idx") : service.index(
        "// Check if it's time to start"
    )]

    assert "display().showCountdown" in countdown
    assert "if (configStore().beepEnabled())" in countdown
    assert countdown.index("display().showCountdown") < countdown.index(
        "if (configStore().beepEnabled())"
    )


def test_m5_serial_diagnostics_do_not_claim_legacy_csv_export():
    main = (ROOT / "src" / "main.cpp").read_text(encoding="utf-8")
    assert "timestamp_app_ms" not in main
    assert "marker" not in main
