import json
from pathlib import Path

import pytest

np = pytest.importorskip("numpy")

from tools.pc_gui.model_inference import (
    ACCEL_G_TO_MS2,
    BIWHEEL3D_FEATURE_DIM,
    CURRENT_BEST_KEY,
    CURRENT_BEST_RECIPE_NAME,
    ModelInferenceError,
    custom_model_spec,
    discover_compatible_models,
    extract_biwheel3d_features,
    model_runtime_status,
    model_spec_runtime_status,
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


def _straight_session() -> dict:
    return {
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
    assert any("Legacy timing" in warning for warning in meta["warnings"])
    assert not meta["physical_sync_verified"]


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


def test_feature_extractor_matches_mobile_python_reference_fixture():
    fixture_path = (
        REPO_ROOT
        / "docs"
        / "model_analysis"
        / "fixtures"
        / "features_v1.json"
    )
    fixture = json.loads(fixture_path.read_text(encoding="utf-8"))
    assert fixture["provenance"]["kind"] == "synthetic"
    assert fixture["provenance"]["recordings_used"] is False
    windows = np.asarray(fixture["windows"], dtype=np.float32)
    expected = np.asarray(fixture["features"], dtype=np.float32)
    actual = extract_biwheel3d_features(windows)
    assert actual.shape == expected.shape
    assert actual.shape[1] == BIWHEEL3D_FEATURE_DIM
    assert np.max(np.abs(actual - expected)) < 1e-5


def test_discover_current_best_recipe_without_user_library(monkeypatch, tmp_path):
    monkeypatch.setenv("WHEELATHLETE_MODEL_DIR", str(tmp_path))
    models = discover_compatible_models(REPO_ROOT)
    assert len(models) == 1
    assert models[0].key == CURRENT_BEST_KEY
    assert models[0].checkpoint.name == CURRENT_BEST_RECIPE_NAME
    assert "XY + Yaw" in models[0].label
    assert models[0].kind == "recipe"


def test_model_library_discovers_onnx_and_recipe(monkeypatch, tmp_path):
    monkeypatch.setenv("WHEELATHLETE_MODEL_DIR", str(tmp_path))
    onnx_path = tmp_path / "my_future_model.onnx"
    onnx_path.write_bytes(b"placeholder")
    models = discover_compatible_models(REPO_ROOT)
    assert any(spec.kind == "onnx" and spec.checkpoint == onnx_path.resolve() for spec in models)
    assert any(spec.key == CURRENT_BEST_KEY for spec in models)


def test_pt_checkpoint_explains_onnx_requirement(tmp_path):
    checkpoint = tmp_path / "legacy.pt"
    checkpoint.write_bytes(b"not-a-real-checkpoint")
    with pytest.raises(ModelInferenceError, match="Export.*ONNX"):
        custom_model_spec(checkpoint)


def test_current_best_runtime_no_longer_requires_torch(monkeypatch, tmp_path):
    monkeypatch.setenv("WHEELATHLETE_MODEL_DIR", str(tmp_path))
    ready, detail = model_runtime_status(REPO_ROOT)
    assert ready
    assert "Model library:" in detail


def test_current_best_runs_straight_dual_wheel_session(monkeypatch, tmp_path):
    monkeypatch.setenv("WHEELATHLETE_MODEL_DIR", str(tmp_path))
    models = discover_compatible_models(REPO_ROOT)
    result = run_session_model(REPO_ROOT, models[0], _straight_session())
    assert result["point_count"] == 120
    assert result["path_length_m"] > 5.0
    assert result["endpoint_m"] == pytest.approx(result["path_length_m"], rel=1e-4)
    assert result["net_yaw_deg"] == pytest.approx(0.0, abs=1e-6)
    assert result["yaw_source"] == "chassis"
    assert result["gyro_scale"] == pytest.approx(1.102644416543689)
    assert result["chassis_yaw_scale"] == pytest.approx(1.1711125569290826)
    assert result["preprocess"]["model_steps"] == 120


def test_bundled_m4_onnx_runs_with_same_feature_contract():
    pytest.importorskip("onnxruntime")
    model_path = (
        REPO_ROOT
        / "applications"
        / "wheelathlete_mobile"
        / "assets"
        / "models"
        / "wheelathlete_biwheel3d_m4.onnx"
    )
    spec = custom_model_spec(model_path)
    ready, detail = model_spec_runtime_status(spec)
    assert ready, detail
    result = run_session_model(REPO_ROOT, spec, _straight_session())
    assert result["model_kind"] == "onnx"
    assert result["runtime_source"] == "onnxruntime_cpu"
    assert result["point_count"] == 120
    assert result["net_yaw_deg"] is None
    assert all(np.isfinite([x, y]).all() for x, y in result["xy"])
