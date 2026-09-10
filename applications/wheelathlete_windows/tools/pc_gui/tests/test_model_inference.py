import json
from pathlib import Path

import pytest

np = pytest.importorskip("numpy")

from tools.pc_gui.model_inference import (  # noqa: E402
    ACCEL_G_TO_MS2,
    BIWHEEL3D_FEATURE_DIM,
    CURRENT_BEST_KEY,
    CURRENT_BEST_RECIPE_NAME,
    ModelInferenceError,
    ModelSpec,
    active_research_dataset_root,
    custom_model_spec,
    discover_compatible_models,
    extract_biwheel3d_features,
    model_runtime_status,
    model_bundle_spec,
    model_spec_runtime_status,
    prepare_dual_windows,
    run_processed_trial_model,
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




def test_center_sensor_is_not_inserted_into_legacy_lr_model_tensor():
    base = {
        "session_id": "legacy_lr",
        "sample_rate_hz": 100,
        "total_missing_samples": 0,
        "samples": {"L": _samples(500, gz_dps=120.0), "R": _samples(500, gz_dps=-80.0)},
    }
    with_center = {
        **base,
        "samples": {
            **base["samples"],
            "C": [
                {**row, "ax": 9999.0, "ay": -9999.0, "az": 12345.0, "gz": 7777.0}
                for row in _samples(500, gz_dps=0.0)
            ],
        },
    }
    lr_windows, _ = prepare_dual_windows(base)
    three_windows, _ = prepare_dual_windows(with_center)
    assert lr_windows.shape == three_windows.shape == (100, 5, 12)
    np.testing.assert_array_equal(lr_windows, three_windows)


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
        REPO_ROOT / "docs" / "model_analysis" / "fixtures" / "features_v1.json"
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
    models = discover_compatible_models(tmp_path)
    assert len(models) == 1
    assert models[0].key == CURRENT_BEST_KEY
    assert models[0].checkpoint.name == CURRENT_BEST_RECIPE_NAME
    assert models[0].label == "Classical v1"
    assert models[0].kind == "recipe"


def test_model_library_discovers_onnx_and_recipe(monkeypatch, tmp_path):
    monkeypatch.setenv("WHEELATHLETE_MODEL_DIR", str(tmp_path))
    onnx_path = tmp_path / "my_future_model.onnx"
    onnx_path.write_bytes(b"placeholder")
    models = discover_compatible_models(REPO_ROOT)
    assert any(
        spec.kind == "onnx" and spec.checkpoint == onnx_path.resolve()
        for spec in models
    )
    assert any(spec.key == CURRENT_BEST_KEY for spec in models)


def _write_bundle(root: Path, **changes) -> Path:
    root.mkdir()
    (root / "model.onnx").write_bytes(b"synthetic portable model")
    payload = {
        "schema_version": 1,
        "model_id": "example.portable.v1",
        "display_name": "Portable v1",
        "model_version": "1.0.0",
        "runtime": {"kind": "onnx", "requires": ["numpy", "onnxruntime"]},
        "artifact": "model.onnx",
        "preprocessing": {
            "id": "biwheel3d_features_v1",
            "sample_rate_hz": 100,
            "feature_dim": 90,
        },
        "required_sensor_roles": ["L", "R"],
        "outputs": [{"name": "x_m", "unit": "m"}, {"name": "y_m", "unit": "m"}],
        "experimental": True,
        "description": "Synthetic test bundle.",
    }
    payload.update(changes)
    manifest = root / "wheelathlete-model.json"
    manifest.write_text(json.dumps(payload), encoding="utf-8")
    return manifest


def test_portable_bundle_is_discovered_without_biwheel3d(monkeypatch, tmp_path):
    library = tmp_path / "library"
    library.mkdir()
    manifest = _write_bundle(library / "portable")
    monkeypatch.setenv("WHEELATHLETE_MODEL_DIR", str(library))

    spec = next(item for item in discover_compatible_models(tmp_path) if item.key == "example.portable.v1")

    assert spec == model_bundle_spec(manifest)
    assert spec.label == "Portable v1"
    assert spec.checkpoint == (manifest.parent / "model.onnx").resolve()
    assert spec.preprocessing_id == "biwheel3d_features_v1"
    assert spec.required_sensor_roles == ("L", "R")
    assert spec.output_capabilities == (("x_m", "m"), ("y_m", "m"))


@pytest.mark.parametrize(
    ("changes", "message"),
    [
        ({"schema_version": 2}, "schema_version"),
        ({"artifact": "missing.onnx"}, "was not found"),
        ({"artifact": "../outside.onnx"}, "escapes"),
        ({"runtime": {"kind": "future_net", "requires": []}}, "Unsupported"),
        ({"required_sensor_roles": ["L", "C"]}, "sensor roles"),
        ({"preprocessing": {"id": "wrong", "sample_rate_hz": 100, "feature_dim": 90}}, "preprocessing.id"),
    ],
)
def test_portable_bundle_rejects_incompatible_contract(tmp_path, changes, message):
    manifest = _write_bundle(tmp_path / "portable", **changes)
    with pytest.raises(ModelInferenceError, match=message):
        model_bundle_spec(manifest)


def test_pt_checkpoint_is_explicit_experimental_pytorch_selection(tmp_path):
    checkpoint = tmp_path / "WheelAthlete-PyTorch-Residual-v1.pt"
    checkpoint.write_bytes(b"placeholder")
    spec = custom_model_spec(checkpoint)
    assert spec.kind == "pytorch_residual"
    assert spec.label == "Residual v1"
    assert "does not replace" in spec.description


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


def _write_synthetic_residual_checkpoint(path: Path) -> None:
    torch = pytest.importorskip("torch")
    from torch import nn

    residual_scale = np.asarray([0.15, 0.23], dtype=np.float32)

    class ResidualBiGRU(nn.Module):
        def __init__(self):
            super().__init__()
            self.gru = nn.GRU(88, 8, num_layers=1, batch_first=True, bidirectional=True)
            self.head = nn.Sequential(
                nn.LayerNorm(16),
                nn.Linear(16, 8),
                nn.SiLU(),
                nn.Dropout(0.0),
                nn.Linear(8, 2),
            )
            self.register_buffer(
                "residual_scale", torch.as_tensor(residual_scale.reshape(1, 1, 2))
            )

    model = ResidualBiGRU()
    # An exact-zero residual makes this fixture deterministic and exercises the
    # real research physics/normalization/model/integration path without athlete data.
    with torch.no_grad():
        model.head[-1].weight.zero_()
        model.head[-1].bias.zero_()
    checkpoint = {
        "schema_version": 1,
        "feature_version": "torch_residual_v1",
        "model": {
            "input_size": 88,
            "hidden_size": 8,
            "num_layers": 1,
            "dropout": 0.0,
            "bidirectional": True,
        },
        "normalizer": {
            "mean": [0.0] * 88,
            "scale": [1.0] * 88,
            "residual_scale": residual_scale.tolist(),
        },
        "state_dict": model.state_dict(),
        "baseline_recipe": {
            "gyro_scale": 1.102644416543689,
            "yaw_scale": 1.0,
            "chassis_yaw_scale": 1.1711125569290826,
            "yaw_delay_frames": 27,
            "yaw_delay_pad": "burst",
            "yaw_source": "auto",
            "speed_mode": "legacy",
            "wheel_radius_m": 0.30,
            "track_width_m": 0.52,
        },
        "selection": {"best_epoch": 0, "test_used_for_selection": False},
    }
    torch.save(checkpoint, path)


def test_model_library_discovers_experimental_pytorch(monkeypatch, tmp_path):
    pytest.importorskip("torch")
    checkpoint = tmp_path / "WheelAthlete-PyTorch-Residual-v1.pt"
    _write_synthetic_residual_checkpoint(checkpoint)
    monkeypatch.setenv("WHEELATHLETE_MODEL_DIR", str(tmp_path))
    models = discover_compatible_models(REPO_ROOT)
    assert any(
        spec.kind == "pytorch_residual" and spec.checkpoint == checkpoint.resolve()
        for spec in models
    )
    assert models[0].key == CURRENT_BEST_KEY


def test_experimental_pytorch_residual_runs_without_replacing_current_best(tmp_path):
    pytest.importorskip("torch")
    checkpoint = tmp_path / "WheelAthlete-PyTorch-Residual-v1.pt"
    _write_synthetic_residual_checkpoint(checkpoint)
    spec = custom_model_spec(checkpoint)
    ready, detail = model_spec_runtime_status(spec)
    assert ready, detail
    result = run_session_model(REPO_ROOT, spec, _straight_session())
    assert result["model_kind"] == "pytorch_residual"
    assert result["runtime_source"] == "pytorch_residual_v1_experimental"
    assert result["point_count"] == 120
    assert result["net_yaw_deg"] == pytest.approx(0.0, abs=1e-5)
    assert result["path_length_m"] > 5.0
    assert result["yaw_delay_frames"] == 0
    assert result["analysis"]["metadata"]["model_key"] == spec.key
    assert any(
        "Experimental PyTorch residual v1" in warning
        for warning in result["analysis"]["metadata"]["warnings"]
    )


def _write_processed_trial(repo_root: Path, name: str = "research_trial.npz") -> Path:
    from tools.pc_gui.biwheel3d_runtime.schema import Trial, TrialMeta

    windows, _ = prepare_dual_windows(_straight_session())
    n = len(windows)
    t = 0.02 + np.arange(n, dtype=np.float64) * 0.05
    x = np.linspace(0.0, 6.0, n, dtype=np.float32)
    xyz = np.column_stack(
        [x, np.zeros(n, dtype=np.float32), np.full(n, 0.30, dtype=np.float32)]
    )
    left = xyz.copy()
    right = xyz.copy()
    left[:, 1] = 0.26
    right[:, 1] = -0.26
    meta = TrialMeta(
        trial_id="SYNTH_GT_01",
        split="val",
        condition="synthetic",
        maneuver="straight",
        R=0.30,
        L_hub=0.52,
        alpha=0.0,
        L_floor=0.52,
        imu_hz=100,
        gt_hz=20,
        sync_ratio=5,
        duration_s=float(n * 0.05),
        n_gt=n,
        n_imu=n * 5,
        has_gt=True,
        athlete="Synthetic",
    )
    zeros = np.zeros(n, dtype=np.float32)
    trial = Trial(
        meta=meta,
        t_gt=t,
        xyz=xyz,
        xyz_left=left,
        xyz_right=right,
        angles=np.zeros((n, 3), dtype=np.float32),
        v=zeros.copy(),
        omega=zeros.copy(),
        theta_left=zeros.copy(),
        theta_right=zeros.copy(),
        imu_left_windows=windows[:, :, :6],
        imu_right_windows=windows[:, :, 6:],
        t_imu=np.arange(n * 5, dtype=np.float64) / 100.0,
        imu_left=windows[:, :, :6].reshape(n * 5, 6),
        imu_right=windows[:, :, 6:].reshape(n * 5, 6),
    )
    path = repo_root / "BiWheel3D" / "data" / "processed_test" / name
    trial.save(path)
    return path


def test_processed_trial_model_returns_gt_overlay_and_rejects_outside_data(tmp_path):
    pytest.importorskip("torch")
    checkpoint = tmp_path / "WheelAthlete-PyTorch-Residual-v1.pt"
    _write_synthetic_residual_checkpoint(checkpoint)
    spec = custom_model_spec(checkpoint)
    trial_path = _write_processed_trial(tmp_path)
    result = run_processed_trial_model(tmp_path, spec, trial_path)
    assert result["session_id"] == "SYNTH_GT_01"
    assert result["point_count"] == 120
    assert len(result["ground_truth_xy"]) == 120
    assert result["gt_diagnostic"]["scope"] == "full_processed_cache_not_support_masked"
    assert np.isfinite(result["gt_diagnostic"]["ate_rmse_m"])
    assert "Research processed NPZ" in result["analysis"]["metadata"]["warnings"][0]

    outside = tmp_path / "outside.npz"
    outside.write_bytes(trial_path.read_bytes())
    with pytest.raises(ModelInferenceError, match="inside"):
        run_processed_trial_model(tmp_path, spec, outside)


def test_optional_research_registry_discovers_experimental_checkpoint(
    monkeypatch, tmp_path
):
    library = tmp_path / "empty_user_models"
    library.mkdir()
    monkeypatch.setenv("WHEELATHLETE_MODEL_DIR", str(library))
    research = tmp_path / "BiWheel3D"
    model_dir = research / "models" / "experimental" / "torch_residual_v1"
    model_dir.mkdir(parents=True)
    checkpoint = model_dir / "model.pt"
    checkpoint.write_bytes(b"placeholder")
    (model_dir / "manifest.json").write_text(
        json.dumps(
            {
                "artifacts": {
                    "pytorch": {
                        "path": "models/experimental/torch_residual_v1/model.pt"
                    }
                }
            }
        ),
        encoding="utf-8",
    )
    registry = research / "registry"
    registry.mkdir()
    (registry / "models.json").write_text(
        json.dumps(
            {
                "schema_version": 1,
                "models": [
                    {
                        "model_id": "biwheel3d:torch_residual_v1",
                        "label": "Experimental PyTorch Residual v1",
                        "status": "experimental_not_promoted",
                        "manifest": "models/experimental/torch_residual_v1/manifest.json",
                    }
                ],
            }
        ),
        encoding="utf-8",
    )
    models = discover_compatible_models(tmp_path)
    matches = [spec for spec in models if spec.checkpoint == checkpoint.resolve()]
    assert len(matches) == 1
    assert matches[0].kind == "pytorch_residual"
    assert matches[0].label == "Residual v1"


def test_active_research_dataset_root_uses_registry_and_falls_back(tmp_path):
    research = tmp_path / "BiWheel3D"
    data = research / "data"
    active = data / "processed_sync_corrected_2026-09-07"
    active.mkdir(parents=True)
    registry = research / "registry"
    registry.mkdir()
    (registry / "datasets.json").write_text(
        json.dumps(
            {
                "schema_version": 1,
                "datasets": [
                    {
                        "dataset_id": "july_corrected_v1",
                        "status": "active_supervised",
                        "path": "data/processed_sync_corrected_2026-09-07",
                    }
                ],
            }
        ),
        encoding="utf-8",
    )
    assert active_research_dataset_root(tmp_path) == active.resolve()
    (registry / "datasets.json").unlink()
    assert active_research_dataset_root(tmp_path) == data.resolve()


def _course_config() -> dict:
    return {
        "schema_version": 1,
        "applies_to_conditions": ["SL", "slalom"],
        "protocol": {
            "start_end_heading_same": True,
            "start_end_position_same_for_complete_course": True,
            "expected_net_heading_rad": 0.0,
        },
        "turn_detection": {
            "threshold_degps": 20.0,
            "merge_gap_frames": 10,
            "min_event_frames": 8,
        },
        "position_closure": {
            "min_turn_events": 8,
            "active_speed_threshold_mps": 0.15,
            "max_abs_speed_correction_mps": 5.0,
        },
        "never_use_c3d_at_inference": True,
    }


def test_slalom_course_math_closes_declared_heading_and_endpoint():
    from tools.pc_gui.slalom_course import (
        apply_slalom_course_constraints,
        integrate_rates_float32,
    )

    rates = np.zeros((320, 2), dtype=np.float32)
    rates[:, 0] = 0.6
    for index, start in enumerate((20, 55, 90, 125, 160, 195, 230, 265)):
        rates[start : start + 12, 1] = np.deg2rad(90.0 if index % 2 == 0 else -90.0)
    rates[:, 1] += np.deg2rad(2.0)
    before_xy, before_yaw = integrate_rates_float32(rates)
    assert abs(np.degrees(before_yaw[-1])) > 5.0
    assert np.linalg.norm(before_xy[-1]) > 0.1

    result = apply_slalom_course_constraints(rates, _course_config())
    after_xy, after_yaw = integrate_rates_float32(result.rates)
    assert result.heading_closure
    assert result.position_closure
    assert result.turn_count == 8
    assert abs(np.degrees(after_yaw[-1])) < 1e-3
    assert np.linalg.norm(after_xy[-1]) < 1e-5
    assert result.speed_correction_rms_mps > 0.0


def test_course_model_is_exact_noop_for_non_slalom(tmp_path):
    pytest.importorskip("torch")
    checkpoint = tmp_path / "model.pt"
    _write_synthetic_residual_checkpoint(checkpoint)
    config_path = tmp_path / "course.json"
    config_path.write_text(json.dumps(_course_config()), encoding="utf-8")
    raw_spec = custom_model_spec(checkpoint)
    course_spec = ModelSpec(
        key="biwheel3d:test_course",
        label="Test course model",
        checkpoint=checkpoint.resolve(),
        description="test",
        kind="pytorch_residual_slalom_course",
        course_config=config_path.resolve(),
    )
    raw = run_session_model(REPO_ROOT, raw_spec, _straight_session())
    constrained = run_session_model(REPO_ROOT, course_spec, _straight_session())
    np.testing.assert_array_equal(np.asarray(constrained["xy"]), np.asarray(raw["xy"]))
    np.testing.assert_array_equal(
        np.asarray(constrained["analysis"]["samples"]),
        np.asarray(raw["analysis"]["samples"]),
    )
    assert constrained["course_constraint"]["applied"] is False
    assert constrained["model_kind"] == "pytorch_residual_slalom_course"


def test_optional_research_registry_discovers_slalom_course_model(
    monkeypatch, tmp_path
):
    library = tmp_path / "empty_user_models"
    library.mkdir()
    monkeypatch.setenv("WHEELATHLETE_MODEL_DIR", str(library))
    research = tmp_path / "BiWheel3D"
    model_dir = research / "models" / "experimental" / "course"
    model_dir.mkdir(parents=True)
    (model_dir / "model.pt").write_bytes(b"placeholder")
    (model_dir / "course.json").write_text(
        json.dumps(_course_config()), encoding="utf-8"
    )
    (model_dir / "manifest.json").write_text(
        json.dumps(
            {
                "artifacts": {
                    "pytorch": {"path": "models/experimental/course/model.pt"},
                    "course_config": {"path": "models/experimental/course/course.json"},
                }
            }
        ),
        encoding="utf-8",
    )
    registry = research / "registry"
    registry.mkdir()
    (registry / "models.json").write_text(
        json.dumps(
            {
                "schema_version": 1,
                "models": [
                    {
                        "model_id": "biwheel3d:test_course",
                        "label": "Test Slalom Course",
                        "status": "experimental_validation_review_only",
                        "kind": "pytorch_residual_slalom_course",
                        "manifest": "models/experimental/course/manifest.json",
                    }
                ],
            }
        ),
        encoding="utf-8",
    )
    models = discover_compatible_models(tmp_path)
    matches = [spec for spec in models if spec.key == "biwheel3d:test_course"]
    assert len(matches) == 1
    assert matches[0].kind == "pytorch_residual_slalom_course"
    assert matches[0].course_config == (model_dir / "course.json").resolve()


def test_discover_and_run_unified_hybrid_model():
    pytest.importorskip("scipy")
    models = discover_compatible_models(REPO_ROOT)
    hybrid_spec = next((spec for spec in models if spec.kind == "unified_hybrid"), None)
    assert hybrid_spec is not None, "Unified Hybrid model must be discovered from research registry"
    assert hybrid_spec.label == "Hybrid v1"
    assert "Unified 5-method hybrid" in hybrid_spec.description

    ready, detail = model_spec_runtime_status(hybrid_spec)
    assert ready, detail

    result = run_session_model(REPO_ROOT, hybrid_spec, _straight_session())
    assert result["model_kind"] == "unified_hybrid"
    assert result["runtime_source"] == "unified_hybrid_v1"
    assert result["point_count"] == 120
    assert result["path_length_m"] > 5.0
    assert result["net_yaw_deg"] is not None
    assert result["analysis"]["metadata"]["model_key"] == hybrid_spec.key
    assert len(result["analysis"]["samples"]) == 120
    first_sample = result["analysis"]["samples"][0]
    assert first_sample["signed_speed_mps"] is not None
    assert first_sample["yaw_rad"] is not None
    assert first_sample["yaw_rate_radps"] is not None
