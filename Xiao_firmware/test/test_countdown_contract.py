import re
from pathlib import Path


HEADER = Path(__file__).parents[1] / "src" / "ble_types.h"


def test_xiao_countdown_matches_m5_four_cues():
    source = HEADER.read_text(encoding="utf-8")
    entries = re.findall(
        r"\{\s*(-?\d+)\s*,\s*\d+\s*,\s*(\d+)\s*\}",
        source[source.index("BLINK_SCHEDULE") : source.index("checkBlinkSchedule")],
    )
    assert entries == [
        ("-3000000", "150"),
        ("-2000000", "150"),
        ("-1000000", "150"),
        ("0", "500"),
    ]


def test_xiao_exposes_countdown_cue_event():
    source = HEADER.read_text(encoding="utf-8")
    assert "CountdownCue" in source
    assert "0x31" in source
    assert "packCountdownCue" in source
