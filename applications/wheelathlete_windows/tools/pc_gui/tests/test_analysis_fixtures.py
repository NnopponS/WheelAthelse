import json
from pathlib import Path

import pytest

from tools.pc_gui.analysis_contract import build_analysis, window_statistics

ROOT = Path(__file__).resolve().parents[5]
FIXTURE = json.loads(
    (ROOT / "docs/model_analysis/fixtures/analysis_v1.json").read_text(encoding="utf-8")
)


def _rounded_floats(value):
    if isinstance(value, float):
        return round(value, 12)
    if isinstance(value, list):
        return [_rounded_floats(item) for item in value]
    if isinstance(value, dict):
        return {key: _rounded_floats(item) for key, item in value.items()}
    return value


@pytest.mark.parametrize("case", FIXTURE["cases"], ids=lambda c: c["id"])
def test_shared_analytical_contract_fixtures(case):
    result = build_analysis(**case["input"])
    assert _rounded_floats(result) == _rounded_floats(case["expected"])
    assert _rounded_floats(window_statistics(result, *case["window"])) == _rounded_floats(
        case["window_statistics"]
    )
    assert json.loads(json.dumps(result, allow_nan=False)) == result
