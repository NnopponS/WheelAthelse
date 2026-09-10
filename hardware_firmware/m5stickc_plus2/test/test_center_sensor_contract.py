from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_center_build_uses_c_role_byte():
    text = (ROOT / "platformio.ini").read_text(encoding="utf-8")
    assert "[env:center]" in text
    center = text.split("[env:center]", 1)[1]
    assert "-DWHEEL_ID=0x43" in center


def test_center_identity_is_yellow_on_m5_display():
    text = (ROOT / "src" / "display.cpp").read_text(encoding="utf-8")
    assert "wheel_id == 'C' ? YELLOW" in text


def test_center_identity_bar_blinks_and_has_recording_heartbeat():
    text = (ROOT / "src" / "display.cpp").read_text(encoding="utf-8")
    assert "if (wheel_id == 'C')" in text
    assert "(now / 500U)" in text
    assert "(now % 1000U) < 150U" in text
    assert 'identity_on ? "C" : ""' in text
    assert "drawChanged(last_identity_" in text


def test_config_accepts_center_role():
    text = (ROOT / "src" / "config_store.h").read_text(encoding="utf-8")
    assert "wheel_id == 0x43" in text
