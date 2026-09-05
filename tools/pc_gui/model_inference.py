from __future__ import annotations

import importlib.util
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any


ACCEL_G_TO_MS2 = 9.80665
TARGET_SAMPLE_HZ = 100
SAMPLES_PER_MODEL_STEP = 5
MIN_MODEL_STEPS = 40


class ModelInferenceError(RuntimeError):
    """Raised when a recording cannot be prepared or a model cannot run safely."""


@dataclass(frozen=True, slots=True)
class ModelSpec:
    key: str
    label: str
    checkpoint: Path
    description: str


def custom_model_spec(checkpoint: Path) -> ModelSpec:
    """Create a model selection for a checkpoint chosen through File Explorer."""
    resolved = checkpoint.expanduser().resolve()
    return ModelSpec(
        key=f"custom:{resolved}",
        label=f"Custom — {resolved.stem}",
        checkpoint=resolved,
        description="User-selected checkpoint from File Explorer; compatibility is checked before inference.",
    )


def discover_compatible_models(repo_root: Path) -> list[ModelSpec]:
    """Return checkpoints that share the active TCN+BiLSTM architecture."""
    checkpoint_dir = repo_root / "BiWheel3D" / "checkpoints" / "tcn_bilstm"
    if not checkpoint_dir.is_dir():
        return []

    preferred = ["m4_final.pt", "best.pt"]
    paths: list[Path] = []
    for name in preferred:
        path = checkpoint_dir / name
        if path.is_file():
            paths.append(path)
    paths.extend(
        path
        for path in sorted(checkpoint_dir.glob("*.pt"))
        if path.name not in preferred
    )

    specs: list[ModelSpec] = []
    for path in paths:
        if path.name == "m4_final.pt":
            label = "TCN + BiLSTM M4 — validated"
            description = "Locked M4 checkpoint; recommended for offline trajectory experiments."
        elif path.name == "best.pt":
            label = "TCN + BiLSTM — best.pt"
            description = "Current best.pt checkpoint using the same compatible architecture."
        else:
            label = f"TCN + BiLSTM — {path.stem}"
            description = "Compatible checkpoint from the active TCN+BiLSTM model family."
        specs.append(
            ModelSpec(
                key=f"tcn_bilstm:{path.name}",
                label=label,
                checkpoint=path,
                description=description,
            )
        )
    return specs


def model_runtime_status(repo_root: Path) -> tuple[bool, str]:
    """Check the optional experimental runtime without importing heavy modules."""
    missing = [
        name
        for name in ("numpy", "torch", "yaml", "scipy")
        if importlib.util.find_spec(name) is None
    ]
    biwheel_root = repo_root / "BiWheel3D"
    if not biwheel_root.is_dir():
        return False, "BiWheel3D folder was not found in this checkout."
    if missing:
        return (
            False,
            "Missing model runtime: "
            + ", ".join(missing)
            + ". Install tools\\pc_gui\\requirements-model.txt.",
        )
    return True, "Experimental BiWheel3D runtime is available (CPU inference)."


def _side_matrix(
    samples: list[dict[str, Any]],
    *,
    source_hz: float,
    np: Any,
) -> tuple[Any, Any]:
    if len(samples) < 2:
        raise ModelInferenceError("Both Left and Right recordings need at least two samples.")

    ordered = sorted(samples, key=lambda row: (float(row.get("t", 0.0)), int(row.get("seq", 0))))
    times = np.asarray([float(row.get("t", 0.0)) for row in ordered], dtype=np.float64)
    seq = np.asarray([int(row.get("seq", index)) for index, row in enumerate(ordered)], dtype=np.int64)
    values = np.asarray(
        [
            [
                float(row.get("ax", 0.0)),
                float(row.get("ay", 0.0)),
                float(row.get("az", 0.0)),
                float(row.get("gx", 0.0)),
                float(row.get("gy", 0.0)),
                float(row.get("gz", 0.0)),
            ]
            for row in ordered
        ],
        dtype=np.float64,
    )

    if not np.all(np.isfinite(times)) or not np.all(np.isfinite(values)):
        raise ModelInferenceError("The selected recording contains non-finite IMU values.")

    # Arrival timestamps can be bursty. When sequence numbers are monotonic, use
    # their known sample cadence while preserving the first observed PC timestamp
    # as the cross-wheel anchor. Missing sequence numbers remain real time gaps.
    seq_delta = seq - seq[0]
    if source_hz > 0 and np.all(seq_delta >= 0) and np.all(np.diff(seq) > 0):
        times = times[0] + seq_delta.astype(np.float64) / float(source_hz)

    order = np.argsort(times, kind="stable")
    times = times[order]
    values = values[order]
    unique_times, unique_indices = np.unique(times, return_index=True)
    values = values[unique_indices]
    if unique_times.size < 2:
        raise ModelInferenceError("The selected recording does not contain a usable time span.")
    return unique_times, values


def prepare_dual_windows(
    session_data: dict[str, Any],
    *,
    target_hz: int = TARGET_SAMPLE_HZ,
) -> tuple[Any, dict[str, Any]]:
    """Convert Results-page g/dps samples into BiWheel3D (T, 5, 12) SI windows."""
    try:
        import numpy as np
    except ImportError as exc:  # pragma: no cover - runtime guard
        raise ModelInferenceError(
            "NumPy is required. Install tools\\pc_gui\\requirements-model.txt."
        ) from exc

    samples = session_data.get("samples")
    if not isinstance(samples, dict):
        raise ModelInferenceError("The selected result has no IMU sample data.")
    left = samples.get("L")
    right = samples.get("R")
    if not isinstance(left, list) or not isinstance(right, list) or not left or not right:
        raise ModelInferenceError("The selected result must contain both Left and Right IMU data.")

    source_hz = float(session_data.get("sample_rate_hz") or target_hz)
    if source_hz <= 0:
        source_hz = float(target_hz)

    t_l, v_l = _side_matrix(left, source_hz=source_hz, np=np)
    t_r, v_r = _side_matrix(right, source_hz=source_hz, np=np)
    start = max(float(t_l[0]), float(t_r[0]))
    end = min(float(t_l[-1]), float(t_r[-1]))
    if end <= start:
        raise ModelInferenceError("Left and Right IMU streams do not overlap in time.")

    sample_count = int(np.floor((end - start) * target_hz)) + 1
    usable_count = (sample_count // SAMPLES_PER_MODEL_STEP) * SAMPLES_PER_MODEL_STEP
    if usable_count < SAMPLES_PER_MODEL_STEP * MIN_MODEL_STEPS:
        min_seconds = MIN_MODEL_STEPS * SAMPLES_PER_MODEL_STEP / target_hz
        raise ModelInferenceError(
            f"Recording is too short for this model. Use at least {min_seconds:.1f} s of dual-wheel data."
        )

    grid = start + np.arange(usable_count, dtype=np.float64) / float(target_hz)
    left_interp = np.column_stack(
        [np.interp(grid, t_l, v_l[:, channel]) for channel in range(6)]
    )
    right_interp = np.column_stack(
        [np.interp(grid, t_r, v_r[:, channel]) for channel in range(6)]
    )

    # Results data are displayed/stored for the GUI in g and deg/s. BiWheel3D
    # was trained on SI: acceleration m/s^2 and angular velocity rad/s.
    left_interp[:, :3] *= ACCEL_G_TO_MS2
    right_interp[:, :3] *= ACCEL_G_TO_MS2
    left_interp[:, 3:] = np.deg2rad(left_interp[:, 3:])
    right_interp[:, 3:] = np.deg2rad(right_interp[:, 3:])

    dual = np.concatenate([left_interp, right_interp], axis=1).astype(np.float32)
    windows = dual.reshape(-1, SAMPLES_PER_MODEL_STEP, 12)

    missing = int(session_data.get("total_missing_samples") or 0)
    warnings: list[str] = []
    if abs(source_hz - target_hz) > 1e-6:
        warnings.append(f"Resampled {source_hz:g} Hz recording to {target_hz} Hz for BiWheel3D.")
    if missing > 0:
        warnings.append(
            f"Recording reports {missing} missing sample(s); interpolation was used for this experimental preview."
        )

    metadata = {
        "source_hz": source_hz,
        "target_hz": target_hz,
        "raw_left_samples": len(left),
        "raw_right_samples": len(right),
        "aligned_samples": int(usable_count),
        "model_steps": int(windows.shape[0]),
        "duration_s": float(usable_count / target_hz),
        "resampled": abs(source_hz - target_hz) > 1e-6,
        "missing_samples": missing,
        "warnings": warnings,
    }
    return windows, metadata


def _apply_checkpoint_metadata(model: Any, state: dict[str, Any]) -> None:
    for key in (
        "climb_res_scale",
        "climb_res_gate_eps",
        "climb_mag_scale",
        "climb_boost_yaw0",
        "climb_boost_yaw_temp",
        "low_yaw_climb_ds_shrink",
        "low_yaw_climb_yaw0",
    ):
        if key in state:
            setattr(model, key, float(state[key]))


def _checkpoint_coverage(model: Any, state_dict: dict[str, Any]) -> float:
    """Return exact-shape parameter coverage for the active runtime architecture."""
    model_state = model.state_dict()
    total = 0
    matched = 0
    for key, expected in model_state.items():
        if not hasattr(expected, "numel"):
            continue
        count = int(expected.numel())
        total += count
        value = state_dict.get(key)
        if value is not None and hasattr(value, "shape") and tuple(value.shape) == tuple(expected.shape):
            matched += count
    return float(matched / total) if total else 0.0


def _normalization_from_checkpoint(
    *,
    spec: ModelSpec,
    state_dict: dict[str, Any],
    np: Any,
) -> tuple[Any, Any, str]:
    norm_path = spec.checkpoint.parent / "imu_norm.npz"
    if norm_path.is_file():
        norm = np.load(norm_path)
        mean = np.asarray(norm["mean"], dtype=np.float32)
        std = np.maximum(np.asarray(norm["std"], dtype=np.float32), 1e-3)
        return mean, std, str(norm_path)

    mean_tensor = state_dict.get("imu_mean")
    std_tensor = state_dict.get("imu_std")
    if mean_tensor is not None and std_tensor is not None:
        mean = np.asarray(mean_tensor.detach().cpu().numpy(), dtype=np.float32)
        std = np.maximum(
            np.asarray(std_tensor.detach().cpu().numpy(), dtype=np.float32),
            1e-3,
        )
        return mean, std, "embedded checkpoint normalization"

    raise ModelInferenceError(
        "The selected checkpoint has no usable normalization. Put imu_norm.npz next to the model "
        "or use a BiWheel3D checkpoint that embeds imu_mean/imu_std."
    )


def run_session_model(
    repo_root: Path,
    spec: ModelSpec,
    session_data: dict[str, Any],
) -> dict[str, Any]:
    """Run one finalized Results recording through a compatible BiWheel3D model."""
    ready, detail = model_runtime_status(repo_root)
    if not ready:
        raise ModelInferenceError(detail)
    if not spec.checkpoint.is_file():
        raise ModelInferenceError(f"Model checkpoint not found: {spec.checkpoint}")

    biwheel_root = repo_root / "BiWheel3D"
    root_text = str(biwheel_root)
    if root_text not in sys.path:
        sys.path.insert(0, root_text)

    try:
        import numpy as np
        import torch
        from biwheel3d.calib_ten_by_five import maybe_load_and_apply_calib
        from biwheel3d.dataset import imu_window_features
        from biwheel3d.experiment import load_experiment_and_method
        from biwheel3d.infer_eval import predict_xyz
        from biwheel3d.method import build_method, load_method_state_dict
    except ImportError as exc:
        raise ModelInferenceError(
            "BiWheel3D runtime could not be imported. Install tools\\pc_gui\\requirements-model.txt."
        ) from exc

    windows, preprocess = prepare_dual_windows(session_data)
    cfg = load_experiment_and_method(
        biwheel_root,
        "configs/experiment.yaml",
        "configs/methods/method_tcn_bilstm.yaml",
    )

    try:
        state = torch.load(spec.checkpoint, map_location="cpu", weights_only=True)
    except Exception as exc:
        raise ModelInferenceError(
            "Could not safely read the selected checkpoint. Only tensor-based PyTorch .pt/.pth "
            "checkpoints are accepted for custom model selection."
        ) from exc
    if not isinstance(state, dict) or not isinstance(state.get("model"), dict):
        raise ModelInferenceError(
            "Selected checkpoint does not contain the expected BiWheel3D 'model' state dictionary."
        )
    checkpoint_state = state["model"]

    model = build_method(
        cfg["method"]["cleaner"],
        cfg["method"]["sequence_model"],
        cfg,
    ).to("cpu")

    coverage = _checkpoint_coverage(model, checkpoint_state)
    if coverage < 0.85:
        raise ModelInferenceError(
            f"Selected checkpoint is not compatible with the current TCN+BiLSTM runtime "
            f"({coverage * 100:.1f}% exact-shape coverage). Choose a compatible BiWheel3D "
            "checkpoint or add an adapter for that architecture."
        )

    mean, std, norm_source = _normalization_from_checkpoint(
        spec=spec,
        state_dict=checkpoint_state,
        np=np,
    )
    if mean.shape != (90,) or std.shape != (90,):
        raise ModelInferenceError(
            f"Selected checkpoint normalization has shape mean={mean.shape}, std={std.shape}; expected (90,)."
        )
    model.set_imu_norm(mean, std)

    load_method_state_dict(model, checkpoint_state, strict=False)
    _apply_checkpoint_metadata(model, state)
    maybe_load_and_apply_calib(model, cfg, biwheel_root, apply_scale=False, verbose=False)
    model.eval()

    features = imu_window_features(windows)
    normalized = ((features - mean) / std).astype(np.float32)
    with torch.inference_mode():
        angles, xyz = predict_xyz(
            model,
            normalized,
            device="cpu",
            mode="full_sequence",
            align_travel=True,
        )
    del angles

    xy = np.asarray(xyz[:, :2], dtype=np.float64)
    if xy.shape[0] < 2 or not np.all(np.isfinite(xy)):
        raise ModelInferenceError("Model returned an invalid 2D trajectory.")
    path_length_m = float(np.linalg.norm(np.diff(xy, axis=0), axis=1).sum())
    endpoint_m = float(np.linalg.norm(xy[-1] - xy[0]))
    extent_x = float(np.ptp(xy[:, 0]))
    extent_y = float(np.ptp(xy[:, 1]))

    phase = state.get("phase")
    return {
        "session_id": str(session_data.get("session_id") or ""),
        "topic": str(session_data.get("topic") or ""),
        "trial_number": session_data.get("trial_number", ""),
        "athlete": str(session_data.get("athlete") or ""),
        "model_key": spec.key,
        "model_label": spec.label,
        "checkpoint": str(spec.checkpoint),
        "checkpoint_phase": str(phase) if phase is not None else "",
        "normalization_source": norm_source,
        "compatibility_coverage": coverage,
        "xy": [(float(x), float(y)) for x, y in xy],
        "point_count": int(xy.shape[0]),
        "path_length_m": path_length_m,
        "endpoint_m": endpoint_m,
        "extent_x_m": extent_x,
        "extent_y_m": extent_y,
        "preprocess": preprocess,
    }
