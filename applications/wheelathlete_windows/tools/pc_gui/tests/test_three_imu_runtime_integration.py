from pathlib import Path

import pytest

np = pytest.importorskip("numpy")
pytest.importorskip("scipy")

from tools.pc_gui.model_inference import (
    THREE_IMU_V2_KEY,
    THREE_IMU_V3_KEY,
    THREE_IMU_V4_KEY,
    THREE_IMU_V5_KEY,
    THREE_IMU_V6_KEY,
    THREE_IMU_V7_KEY,
    THREE_IMU_V8_KEY,
    ModelInferenceError,
    _three_imu_spec,
    discover_compatible_models,
    model_runtime_status,
    run_session_model,
)


REPO_ROOT = Path(__file__).resolve().parents[5]


def _stationary_samples(count: int = 220) -> list[dict[str, float | int]]:
    return [
        {
            "t": index / 100.0,
            "seq": index,
            "ax": 0.0,
            "ay": 0.0,
            "az": 1.0,
            "gx": 0.0,
            "gy": 0.0,
            "gz": 0.0,
        }
        for index in range(count)
    ]


def _three_imu_session() -> dict:
    return {
        "session_id": "three_imu_runtime_smoke",
        "topic": "runtime-smoke",
        "trial_number": 1,
        "athlete": "Synthetic",
        "sample_rate_hz": 100,
        "total_missing_samples": 0,
        "samples": {
            "L": _stationary_samples(),
            "R": _stationary_samples(),
            "C": _stationary_samples(),
        },
    }


def test_three_imu_runtime_is_ready_and_lifecycle_order_is_stable():
    ready, detail = model_runtime_status(REPO_ROOT)
    assert ready, detail
    models = discover_compatible_models(REPO_ROOT, lifecycle_only=True)
    assert [model.key for model in models] == [THREE_IMU_V3_KEY, THREE_IMU_V2_KEY]
    assert [model.kind for model in models] == ["three_imu_v3", "three_imu_v2"]


def test_v8_is_available_only_as_research_candidate_and_runs_c3d_free():
    models = {model.key: model for model in discover_compatible_models(REPO_ROOT)}
    spec = models[THREE_IMU_V8_KEY]
    assert spec.kind == "three_imu_v8"
    assert spec.experimental is True
    assert spec.label == "SOF-3IMU v2 (Research - Development Candidate)"

    result = run_session_model(REPO_ROOT, spec, _three_imu_session())
    assert result["runtime_source"] == "three_imu_odometry_v8"
    assert result["point_count"] == 220
    assert result["path_length_m"] == pytest.approx(0.0, abs=1e-9)
    assert any("C3D" in warning for warning in result["analysis"]["metadata"]["warnings"])


def test_v7_historical_sof_runtime_remains_reproducible():
    spec = _three_imu_spec(7)
    assert spec.kind == "three_imu_v7"
    assert spec.experimental is True
    assert spec.label == "SOF-3IMU v1 (Historical Research)"

    result = run_session_model(REPO_ROOT, spec, _three_imu_session())
    assert result["runtime_source"] == "three_imu_odometry_v7"
    assert result["point_count"] == 220
    assert result["path_length_m"] == pytest.approx(0.0, abs=1e-9)
    assert any("C3D" in warning for warning in result["analysis"]["metadata"]["warnings"])


def test_v6_historical_grf_runtime_remains_reproducible():
    spec = _three_imu_spec(6)
    assert spec.kind == "three_imu_v6"
    assert spec.experimental is True
    assert spec.label == "GRF-3IMU v3 (Historical Research)"

    result = run_session_model(REPO_ROOT, spec, _three_imu_session())
    assert result["runtime_source"] == "three_imu_odometry_v6"
    assert result["point_count"] == 220
    assert result["path_length_m"] == pytest.approx(0.0, abs=1e-9)
    assert any("C3D" in warning for warning in result["analysis"]["metadata"]["warnings"])


def test_v5_historical_grf_runtime_remains_reproducible():
    spec = _three_imu_spec(5)
    assert spec.kind == "three_imu_v5"
    assert spec.experimental is True
    assert spec.label == "GRF-3IMU v2 (Historical Research)"

    result = run_session_model(REPO_ROOT, spec, _three_imu_session())
    assert result["runtime_source"] == "three_imu_odometry_v5"
    assert result["point_count"] == 220
    assert result["path_length_m"] == pytest.approx(0.0, abs=1e-9)
    assert any("C3D" in warning for warning in result["analysis"]["metadata"]["warnings"])


@pytest.mark.parametrize(
    ("model_index", "expected_kind", "expected_runtime"),
    [
        (0, "three_imu_v3", "three_imu_odometry_v3"),
        (1, "three_imu_v2", "three_imu_odometry_v2"),
    ],
)
def test_three_imu_models_run_end_to_end_without_legacy_lr_dispatch(
    model_index: int,
    expected_kind: str,
    expected_runtime: str,
):
    spec = discover_compatible_models(REPO_ROOT, lifecycle_only=True)[model_index]
    result = run_session_model(REPO_ROOT, spec, _three_imu_session())

    assert result["model_kind"] == expected_kind
    assert result["runtime_source"] == expected_runtime
    assert result["point_count"] == 220
    assert result["preprocess"]["model_steps"] == 220
    assert result["path_length_m"] == pytest.approx(0.0, abs=1e-9)
    assert result["endpoint_m"] == pytest.approx(0.0, abs=1e-9)
    metadata = result["analysis"]["metadata"]
    assert metadata["model_key"] == spec.key
    assert "(T,18)" in metadata["model_input_layout"]
    assert len(metadata["model_input_sha256"]) == 64
    assert any("C3D is never used" in warning for warning in metadata["warnings"])


def test_three_imu_runtime_rejects_missing_center_sensor_cleanly():
    spec = discover_compatible_models(REPO_ROOT, lifecycle_only=True)[0]
    session = _three_imu_session()
    del session["samples"]["C"]
    with pytest.raises(ModelInferenceError):
        run_session_model(REPO_ROOT, spec, session)
