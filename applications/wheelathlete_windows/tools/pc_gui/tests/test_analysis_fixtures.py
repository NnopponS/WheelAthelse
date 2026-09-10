import json
from pathlib import Path

import pytest

from tools.pc_gui.analysis_contract import build_analysis, window_statistics

ROOT = Path(__file__).resolve().parents[5]
FIXTURE = json.loads(
    (ROOT / "docs/model_analysis/fixtures/analysis_v1.json").read_text(encoding="utf-8")
)


@pytest.mark.parametrize("case", FIXTURE["cases"], ids=lambda c: c["id"])
def test_shared_analytical_contract_fixtures(case):
    result = build_analysis(**case["input"])
    assert result == case["expected"]
    assert window_statistics(result, *case["window"]) == case["window_statistics"]
    assert json.loads(json.dumps(result, allow_nan=False)) == result
