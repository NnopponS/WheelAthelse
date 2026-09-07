from pathlib import Path

import pytest

np = pytest.importorskip("numpy")

from tools.pc_gui.model_inference import (
    ACCEL_G_TO_MS2,
    CURRENT_BEST_KEY,
    discover_compatible_models,
    model_runtime_status,
    prepare_dual_windows,
    run_session_model,
)


REPO_ROOT = Path(__file__).resolve().parents[5]


def _samples(
    count: int,
    *,
    time_offset: float = 0.0,
    gz_dps: float = 180.0,
) -> list[dict[str, float | int]]:
    return [
        {
            "t": time_offset + index / 100.0,
            "seq": index,
            "ax": 0.0,
            "ay": 1.0,
            "az": 0.0,
            "gx": 0.0,
            "gy": 0.0,
            "gz": gz_dps,
        }
        for index in range(count)
    ]


def test_prepare_dual_windows_matches_biwheel3d_contract_and_si_units():
    session = {
        "session_id": "test",
        "sample_rate_hz": 100,
        "total_missing_samples": 0,
        "samples": {"L": _samples(500), "R": _samples(500)},
    }
    windows, meta = prepare_dual_windows(session)
    assert windows.shape == (100, 5, 12)
    assert windows.dtype == np.float32
    assert windows[0, 0, 1] == pytest.approx(ACCEL_G_TO_MS2)
    assert windows[0, 0, 5] == pytest.approx(np.pi)
    assert windows[0, 0, 7] == pytest.approx(ACCEL_G_TO_MS2)
    assert windows[0, 0, 11] == pytest.approx(np.pi)
    assert meta["target_hz"] == 100
    assert meta["model_steps"] == 100
    assert not meta["resampled"]
    assert meta["warnings"] == []


def test_prepare_dual_windows_resamples_non_native_rate_and_surfaces_warning():
    session = {
        "session_id": "resampled",
        "sample_rate_hz": 200,
        "total_missing_samples": 3,
        "samples": {"L": _samples(500), "R": _samples(500)},
    }
    windows, meta = prepare_dual_windows(session)
    assert windows.shape[1:] == (5, 12)
    assert meta["resampled"]
    assert meta["missing_samples"] == 3
    assert any("Resampled" in warning for warning in meta["warnings"])
    assert any("missing sample" in warning for warning in meta["warnings"])


def test_discover_current_best_xy_yaw_recipe():
    models = discover_compatible_models(REPO_ROOT)
    assert len(models) == 1
    assert models[0].key == CURRENT_BEST_KEY
    assert models[0].checkpoint.name == "current_best_summary.json"
    assert "XY + Yaw" in models[0].label
    assert "27-frame" in models[0].description


def test_current_best_runtime_no_longer_requires_torch():
    ready, detail = model_runtime_status(REPO_ROOT)
    assert ready
    assert "no PyTorch or external checkout required" in detail


def test_current_best_runs_straight_dual_wheel_session():
    models = discover_compatible_models(REPO_ROOT)
    session = {
        "session_id": "straight_runtime",
        "topic": "Straight",
        "trial_number": 1,
        "athlete": "Test",
        "sample_rate_hz": 100,
        "total_missing_samples": 0,
        "samples": {
            "L": _samples(600, gz_dps=180.0),
            "R": _samples(600, gz_dps=-180.0),
        },
    }
    result = run_session_model(REPO_ROOT, models[0], session)
    assert result["point_count"] == 120
    assert result["path_length_m"] > 5.0
    assert result["endpoint_m"] == pytest.approx(result["path_length_m"], rel=1e-4)
    assert result["net_yaw_deg"] == pytest.approx(0.0, abs=1e-6)
    assert result["yaw_source"] == "chassis"
    assert result["gyro_scale"] == pytest.approx(1.102644416543689)
    assert result["chassis_yaw_scale"] == pytest.approx(1.1711125569290826)
    assert result["preprocess"]["model_steps"] == 120
