from pathlib import Path

import pytest

np = pytest.importorskip("numpy")

from tools.pc_gui.model_inference import (
    ACCEL_G_TO_MS2,
    custom_model_spec,
    discover_compatible_models,
    prepare_dual_windows,
)


REPO_ROOT = Path(__file__).resolve().parents[3]


def _samples(count: int, *, time_offset: float = 0.0) -> list[dict[str, float | int]]:
    return [
        {
            "t": time_offset + index / 100.0,
            "seq": index,
            "ax": 1.0,
            "ay": 0.0,
            "az": 0.0,
            "gx": 0.0,
            "gy": 0.0,
            "gz": 180.0,
        }
        for index in range(count)
    ]


def test_prepare_dual_windows_matches_biwheel3d_contract_and_si_units():
    session = {
        "session_id": "test",
        "sample_rate_hz": 100,
        "total_missing_samples": 0,
        "samples": {
            "L": _samples(500),
            "R": _samples(500),
        },
    }

    windows, meta = prepare_dual_windows(session)

    assert windows.shape == (100, 5, 12)
    assert windows.dtype == np.float32
    assert windows[0, 0, 0] == pytest.approx(ACCEL_G_TO_MS2)
    assert windows[0, 0, 5] == pytest.approx(np.pi)
    assert windows[0, 0, 6] == pytest.approx(ACCEL_G_TO_MS2)
    assert windows[0, 0, 11] == pytest.approx(np.pi)
    assert meta["target_hz"] == 100
    assert meta["model_steps"] == 100
    assert not meta["resampled"]
    assert meta["warnings"] == []


def test_prepare_dual_windows_resamples_non_native_rate_and_surfaces_warning():
    left = _samples(500)
    right = _samples(500)
    session = {
        "session_id": "resampled",
        "sample_rate_hz": 200,
        "total_missing_samples": 3,
        "samples": {"L": left, "R": right},
    }

    windows, meta = prepare_dual_windows(session)

    assert windows.shape[1:] == (5, 12)
    assert meta["resampled"]
    assert meta["missing_samples"] == 3
    assert any("Resampled" in warning for warning in meta["warnings"])
    assert any("missing sample" in warning for warning in meta["warnings"])


def test_discover_compatible_models_prefers_validated_m4():
    models = discover_compatible_models(REPO_ROOT)

    assert models
    assert models[0].checkpoint.name == "m4_final.pt"
    assert "validated" in models[0].label.lower()
    assert all(model.checkpoint.parent.name == "tcn_bilstm" for model in models)


def test_custom_model_spec_accepts_user_selected_checkpoint(tmp_path: Path):
    checkpoint = tmp_path / "experiment_candidate.pth"
    checkpoint.write_bytes(b"placeholder")

    spec = custom_model_spec(checkpoint)

    assert spec.checkpoint == checkpoint.resolve()
    assert spec.key.startswith("custom:")
    assert "experiment_candidate" in spec.label
    assert "File Explorer" in spec.description
