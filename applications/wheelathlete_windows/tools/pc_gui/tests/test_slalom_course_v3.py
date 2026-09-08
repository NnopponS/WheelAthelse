from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pytest

from tools.pc_gui.slalom_course_v3 import (
    apply_linear_calibration,
    apply_slalom_calibrated_v3,
    detect_turn_events_sign_aware,
    major_turn_pattern,
)


def _zero_config():
    return {
        "schema_version": 3,
        "protocol": {
            "start_end_heading_same": True,
            "start_end_position_same_for_complete_course": True,
            "expected_net_heading_rad": 0.0,
        },
        "calibration": {
            "yaw_residual_coefficients": [0.0] * 10,
            "speed_residual_coefficients": [0.0] * 9,
            "max_abs_yaw_calibration_degps": 5.0,
            "max_abs_speed_calibration_mps": 0.05,
        },
        "turn_detection": {
            "threshold_degps": 20.0,
            "merge_gap_frames": 10,
            "min_event_frames": 8,
        },
        "complete_course": {
            "major_turn_min_abs_deg": 60.0,
            "expected_major_sign_pattern": [-1, 1, -1, -1, 1, -1, 1, 1],
        },
        "position_closure": {
            "active_speed_threshold_mps": 0.15,
            "probe_max_abs_speed_correction_mps": 10.0,
            "max_rms_speed_correction_mps": 10.0,
            "max_abs_speed_correction_mps": 10.0,
            "max_rms_fraction_median_speed": 100.0,
            "max_abs_fraction_median_speed": 100.0,
        },
    }


def _full_rates():
    rates = np.zeros((620, 2), dtype=np.float32)
    rates[:, 0] = 0.4
    signs = [-1, 1, -1, -1, 1, -1, 1, 1]
    for index, sign in enumerate(signs):
        start = 35 + index * 70
        rates[start : start + 22, 1] = sign * np.deg2rad(70.0)
    return rates


def test_sign_aware_detector_does_not_merge_opposite_turns():
    yaw = np.zeros(100, dtype=np.float32)
    yaw[10:30] = np.deg2rad(60)
    yaw[35:55] = np.deg2rad(-60)
    assert detect_turn_events_sign_aware(
        yaw, merge_gap_frames=10, min_event_frames=8
    ) == [(10, 30), (35, 55)]


def test_zero_calibration_is_identity_and_reports_guard_pass():
    predicted = np.zeros((30, 2), dtype=np.float32)
    predicted[:, 0] = 0.4
    residual = predicted.copy()
    center = predicted.copy()
    output, metadata = apply_linear_calibration(
        predicted, residual, center, _zero_config()["calibration"]
    )
    np.testing.assert_array_equal(output, predicted)
    assert metadata["calibration_applied"] is True


def test_calibration_guard_falls_back_to_raw_rates():
    predicted = np.zeros((30, 2), dtype=np.float32)
    predicted[:, 0] = 0.4
    residual = predicted.copy()
    center = predicted.copy()
    config = _zero_config()["calibration"]
    config["yaw_residual_coefficients"][0] = np.deg2rad(8.0)
    output, metadata = apply_linear_calibration(predicted, residual, center, config)
    np.testing.assert_array_equal(output, predicted)
    assert metadata["calibration_applied"] is False
    assert "guard_exceeded" in metadata["calibration_reason"]


def test_full_course_pattern_closes_heading_and_position_deterministically():
    predicted = _full_rates()
    config = _zero_config()
    events = detect_turn_events_sign_aware(predicted[:, 1])
    assert major_turn_pattern(predicted[:, 1], events) == tuple(
        config["complete_course"]["expected_major_sign_pattern"]
    )
    first = apply_slalom_calibrated_v3(predicted, predicted, predicted, config)
    second = apply_slalom_calibrated_v3(predicted, predicted, predicted, config)
    assert first.complete_course and first.heading_closure and first.position_closure
    assert abs(first.final_net_heading_deg) < 1e-3
    assert first.endpoint_after_m < 2e-5
    np.testing.assert_array_equal(first.rates, second.rates)


def test_frozen_v3_config_has_no_test_evaluation_or_c3d_inference():
    root = Path(__file__).resolve().parents[5]
    config_path = root / "BiWheel3D" / "configs" / "slalom_calibrated_course_v3.json"
    if not config_path.is_file():
        pytest.skip(f"BiWheel3D research config not present at {config_path}")
    config = json.loads(config_path.read_text(encoding="utf-8"))
    assert config["historical_test_evaluated"] is False
    assert config["never_use_c3d_at_inference"] is True
    assert len(config["calibration"]["yaw_residual_coefficients"]) == 10
    assert len(config["calibration"]["speed_residual_coefficients"]) == 9
