from pathlib import Path


GUI_ROOT = Path(__file__).resolve().parents[1]


def test_python_gui_source_has_no_common_utf8_mojibake() -> None:
    text = (GUI_ROOT / "main_window.py").read_text(encoding="utf-8")
    bad_sequences = ("Â±", "Â°", "Â·", "â€”", "â€¦", "â€¢", "â†’")
    assert not any(sequence in text for sequence in bad_sequences)


def test_python_gui_keeps_expected_unit_labels() -> None:
    text = (GUI_ROOT / "main_window.py").read_text(encoding="utf-8")
    assert '"±4g"' in text
    assert '"±2000°/s"' in text
