import json
from pathlib import Path

import numpy as np
import pytest

from tools.pc_gui.slalom_course import (
    apply_slalom_course_constraints,
    integrate_rates_float32,
)


REPO_ROOT = Path(__file__).resolve().parents[5]


def test_slalom_course_matches_shared_synthetic_fixture():
    fixture = json.loads(
        (
            REPO_ROOT / "docs" / "model_analysis" / "fixtures" / "slalom_course_v1.json"
        ).read_text(encoding="utf-8")
    )
    assert fixture["provenance"]["kind"] == "synthetic"
    assert fixture["provenance"]["recordings_used"] is False
    rates = np.asarray(fixture["input_rates"], dtype=np.float32)
    expected_rates = np.asarray(fixture["expected_rates"], dtype=np.float32)
    result = apply_slalom_course_constraints(rates, fixture["config"])
    np.testing.assert_allclose(result.rates, expected_rates, rtol=0.0, atol=2e-6)
    assert result.turn_count == fixture["expected"]["turn_count"]
    assert result.heading_closure is fixture["expected"]["heading_closure"]
    assert result.position_closure is fixture["expected"]["position_closure"]
    assert result.removed_net_heading_deg == pytest.approx(
        fixture["expected"]["removed_net_heading_deg"], abs=2e-5
    )
    assert result.speed_correction_rms_mps == pytest.approx(
        fixture["expected"]["speed_correction_rms_mps"], abs=2e-6
    )
    assert result.speed_correction_max_abs_mps == pytest.approx(
        fixture["expected"]["speed_correction_max_abs_mps"], abs=2e-6
    )
    assert result.endpoint_before_m == pytest.approx(
        fixture["expected"]["endpoint_before_m"], abs=2e-6
    )
    assert result.endpoint_after_m == pytest.approx(
        fixture["expected"]["endpoint_after_m"], abs=2e-6
    )
    _, yaw = integrate_rates_float32(result.rates)
    assert float(yaw[-1]) == pytest.approx(
        fixture["expected"]["final_heading_rad"], abs=5e-6
    )
