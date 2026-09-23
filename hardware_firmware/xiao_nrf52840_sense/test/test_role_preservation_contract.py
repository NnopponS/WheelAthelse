from pathlib import Path


ROOT = Path(__file__).parents[1]


def test_xiao_setup_preserves_a_valid_saved_board_role_and_name():
    config_store = (ROOT / "src" / "config_store.cpp").read_text(encoding="utf-8")
    main = (ROOT / "src" / "main.cpp").read_text(encoding="utf-8")
    setup = main[main.index("void setup()") : main.index("void loop()")]
    disconnected_csv = main[main.index("// Serial CSV debug") :]

    assert "configStore().begin(WHEEL);" in setup
    assert setup.index("configStore().begin(WHEEL);") < setup.index(
        'Serial.printf("Wheel: %c\\n", configStore().wheelChar());'
    )
    assert config_store.count("config_.wheel_id = default_wheel_id;") >= 2
    assert "configStore().setWheel(" not in setup
    assert "configStore().setName(" not in setup
    assert "ble().begin(configStore().wheelChar());" in setup
    assert "configStore().wheelChar()," in disconnected_csv
    assert "                          WHEEL," not in disconnected_csv
