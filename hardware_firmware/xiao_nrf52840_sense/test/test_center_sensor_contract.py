from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_center_build_uses_c_role_byte():
    text = (ROOT / "platformio.ini").read_text(encoding="utf-8")
    assert "[env:center]" in text
    center = text.split("[env:center]", 1)[1]
    assert "-DWHEEL_ID=0x43" in center


def test_center_identity_is_green_only():
    text = (ROOT / "src" / "ble_service.cpp").read_text(encoding="utf-8")
    assert "wheel_id_ == 0x43" in text
    assert "Green on the XIAO RGB LED" in text
    assert "digitalWrite(LED_RED, HIGH)" in text
    assert "digitalWrite(LED_GREEN, on ? LOW : HIGH)" in text
    assert "digitalWrite(LED_BLUE, HIGH)" in text
    assert "Yellow on the XIAO RGB LED" not in text


def test_config_accepts_center_role():
    text = (ROOT / "src" / "config_store.h").read_text(encoding="utf-8")
    assert "wheel_id == 0x43" in text


def test_center_connected_does_not_blink():
    text = (ROOT / "src" / "ble_service.cpp").read_text(encoding="utf-8")
    connected_block = text[
        text.index("else if (state_ == BleState::Connected || state_ == BleState::Countdown)") :
        text.index("else if (state_ == BleState::Recording)")
    ]
    assert "millis() / 500" not in connected_block
    assert "set_identity(true);" in connected_block
