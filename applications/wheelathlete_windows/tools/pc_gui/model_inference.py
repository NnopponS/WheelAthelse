from __future__ import annotations

import importlib.util
import json
import os
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any


ACCEL_G_TO_MS2 = 9.80665
TARGET_SAMPLE_HZ = 100
SAMPLES_PER_MODEL_STEP = 5
MIN_MODEL_STEPS = 40
BIWHEEL3D_FEATURE_DIM = 90
CURRENT_BEST_WHEEL_RADIUS_M = 0.30
CURRENT_BEST_TRACK_WIDTH_M = 0.52
CURRENT_BEST_KEY = "biwheel3d:xy_yaw_current_best"
CURRENT_BEST_RECIPE_NAME = "BiWheel3D-XY-Yaw-current_best.json"


class ModelInferenceError(RuntimeError):
    """Raised when a recording cannot be prepared or a trajectory model cannot run safely."""


@dataclass(frozen=True, slots=True)
class ModelSpec:
    key: str
    label: str
    checkpoint: Path
    description: str
    kind: str = "recipe"
    bundled: bool = False


def model_library_root() -> Path:
    """Return the user-editable WheelAthlete model library."""
    override = os.environ.get("WHEELATHLETE_MODEL_DIR", "").strip()
    if override:
        return Path(override).expanduser().resolve()
    return (Path.home() / "Documents" / "WheelAthlete" / "Model").resolve()


def _runtime_root() -> Path:
    return Path(__file__).resolve().parent / "biwheel3d_runtime"


def _bundled_current_best_recipe() -> Path:
    return _runtime_root() / CURRENT_BEST_RECIPE_NAME


def _recipe_spec(path: Path, *, bundled: bool = False, strict: bool = True) -> ModelSpec | None:
    resolved = path.expanduser().resolve()
    try:
        payload = json.loads(resolved.read_text(encoding="utf-8"))
    except Exception as exc:
        if strict:
            raise ModelInferenceError(f"Could not read BiWheel3D recipe: {resolved}") from exc
        return None
    if not isinstance(payload, dict) or payload.get("model_type") != "biwheel3d_xy_yaw_recipe":
        if strict:
            raise ModelInferenceError(
                "Recipe JSON is not a supported BiWheel3D XY + Yaw model recipe. "
                "Choose an ONNX model or a JSON file with model_type='biwheel3d_xy_yaw_recipe'."
            )
        return None
    key = str(payload.get("model_id") or f"recipe:{resolved}")
    label = str(payload.get("label") or resolved.stem)
    description = str(payload.get("description") or payload.get("recipe") or "BiWheel3D XY + Yaw recipe")
    return ModelSpec(
        key=key,
        label=label,
        checkpoint=resolved,
        description=description,
        kind="recipe",
        bundled=bundled,
    )


def custom_model_spec(checkpoint: Path) -> ModelSpec:
    """Build a validated model selection from a user-selected file."""
    resolved = checkpoint.expanduser().resolve()
    if not resolved.is_file():
        raise ModelInferenceError(f"Model file was not found: {resolved}")
    suffix = resolved.suffix.lower()
    if suffix == ".onnx":
        stem = resolved.stem.lower()
        label = "BiWheel3D M4 - ONNX" if "biwheel3d" in stem and "m4" in stem else f"ONNX - {resolved.stem}"
        return ModelSpec(
            key=f"onnx:{resolved}",
            label=label,
            checkpoint=resolved,
            description=(
                "ONNX trajectory model using the BiWheel3D 90-feature input contract. "
                "Runs locally with ONNX Runtime on CPU."
            ),
            kind="onnx",
        )
    if suffix == ".json":
        spec = _recipe_spec(resolved, bundled=False, strict=True)
        assert spec is not None
        return spec
    if suffix in {".pt", ".pth"}:
        raise ModelInferenceError(
            "PyTorch .pt/.pth checkpoints are not loaded by the lean Windows app. "
            "Export the checkpoint to the BiWheel3D ONNX format, then browse the .onnx file."
        )
    raise ModelInferenceError("Choose a BiWheel3D .onnx model or supported .json recipe.")


def _candidate_model_dirs() -> list[Path]:
    roots = [model_library_root()]
    if getattr(sys, "frozen", False):
        exe_dir = Path(sys.executable).resolve().parent
        roots.extend([exe_dir / "Model", exe_dir.parent / "Model"])
    unique: list[Path] = []
    seen: set[Path] = set()
    for root in roots:
        try:
            resolved = root.resolve()
        except OSError:
            resolved = root
        if resolved not in seen:
            seen.add(resolved)
            unique.append(resolved)
    return unique


def discover_compatible_models(repo_root: Path) -> list[ModelSpec]:
    """Discover built-in recipes and user models from Documents/WheelAthlete/Model."""
    del repo_root
    discovered: list[ModelSpec] = []
    seen_keys: set[str] = set()
    seen_paths: set[Path] = set()

    # Prefer a user-visible copy of the current recipe when setup has seeded it.
    for root in _candidate_model_dirs():
        if not root.is_dir():
            continue
        for path in sorted(root.glob("*.json"), key=lambda item: item.name.lower()):
            spec = _recipe_spec(path, bundled=False, strict=False)
            if spec is None or spec.key in seen_keys:
                continue
            discovered.append(spec)
            seen_keys.add(spec.key)
            seen_paths.add(spec.checkpoint)

    bundled_recipe = _bundled_current_best_recipe()
    if CURRENT_BEST_KEY not in seen_keys and bundled_recipe.is_file():
        spec = _recipe_spec(bundled_recipe, bundled=True, strict=False)
        if spec is not None:
            discovered.insert(0, spec)
            seen_keys.add(spec.key)
            seen_paths.add(spec.checkpoint)

    onnx_specs: list[ModelSpec] = []
    for root in _candidate_model_dirs():
        if not root.is_dir():
            continue
        for path in sorted(root.glob("*.onnx"), key=lambda item: item.name.lower()):
            try:
                resolved = path.resolve()
            except OSError:
                continue
            if resolved in seen_paths:
                continue
            try:
                spec = custom_model_spec(resolved)
            except ModelInferenceError:
                continue
            onnx_specs.append(spec)
            seen_paths.add(resolved)

    # Keep the calibrated current-best recipe first, then browseable learned models.
    return discovered + onnx_specs


def model_runtime_status(repo_root: Path) -> tuple[bool, str]:
    """Check the common MODEL runtime without importing heavy optional providers."""
    del repo_root
    if importlib.util.find_spec("numpy") is None:
        return False, "NumPy is required for BiWheel3D trajectory analysis."
    runtime = _runtime_root()
    if not (runtime / "yaw_ab.py").is_file():
        return False, "Bundled BiWheel3D XY + Yaw runtime is missing."
    if not _bundled_current_best_recipe().is_file():
        return False, "Bundled BiWheel3D current_best recipe is missing."
    return True, f"Model library: {model_library_root()}"


def model_spec_runtime_status(spec: ModelSpec) -> tuple[bool, str]:
    """Validate dependencies for the selected model without executing inference."""
    if importlib.util.find_spec("numpy") is None:
        return False, "NumPy is required for trajectory analysis."
    if not spec.checkpoint.is_file():
        return False, f"Model file not found: {spec.checkpoint}"
    if spec.kind == "onnx":
        if importlib.util.find_spec("onnxruntime") is None:
            return False, "ONNX Runtime is required for this model."
        return True, "ONNX Runtime CPU provider ready."
    if spec.kind == "recipe":
        if not (_runtime_root() / "yaw_ab.py").is_file():
            return False, "BiWheel3D XY + Yaw runtime is missing."
        return True, "BiWheel3D XY + Yaw recipe ready."
    return False, f"Unsupported model kind: {spec.kind}"


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
        raise ModelInferenceError("NumPy is required for BiWheel3D trajectory analysis.") from exc

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
            f"Recording is too short for this trajectory method. Use at least {min_seconds:.1f} s of dual-wheel data."
        )

    grid = start + np.arange(usable_count, dtype=np.float64) / float(target_hz)
    left_interp = np.column_stack([np.interp(grid, t_l, v_l[:, channel]) for channel in range(6)])
    right_interp = np.column_stack([np.interp(grid, t_r, v_r[:, channel]) for channel in range(6)])

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


def extract_biwheel3d_features(windows: Any) -> Any:
    """Return the exact BiWheel3D protocol-v10b `(T, 90)` feature tensor."""
    try:
        import numpy as np
        from .biwheel3d_runtime.imu_frame import canonicalize_dual_windows, demod_rim_accel
    except ImportError as exc:  # pragma: no cover - runtime guard
        raise ModelInferenceError("BiWheel3D feature extraction dependencies are unavailable.") from exc

    w = canonicalize_dual_windows(np.asarray(windows, dtype=np.float32))
    if w.ndim != 3 or w.shape[1] != SAMPLES_PER_MODEL_STEP or w.shape[2] != 12:
        raise ModelInferenceError(f"Expected BiWheel3D windows shaped (T,5,12), got {w.shape}.")
    if w.shape[0] < MIN_MODEL_STEPS:
        raise ModelInferenceError(f"BiWheel3D requires at least {MIN_MODEL_STEPS} model steps.")

    flat = w.reshape(w.shape[0], 60)
    mu = w.mean(axis=1)
    dt = 0.05
    radius_m = CURRENT_BEST_WHEEL_RADIUS_M
    track_m = CURRENT_BEST_TRACK_WIDTH_M
    g = ACCEL_G_TO_MS2
    lgz, rgz = mu[:, 5], mu[:, 11]
    kin = np.stack(
        [
            0.5 * (lgz - rgz) * dt,
            0.5 * (lgz + rgz) * dt,
            (radius_m / track_m) * (rgz - lgz) * dt,
            (radius_m / track_m) * (lgz - rgz) * dt,
            np.abs(lgz) * dt,
            np.abs(rgz) * dt,
        ],
        axis=-1,
    ).astype(np.float32)

    lf, ll = demod_rim_accel(mu[:, 0], mu[:, 1], mu[:, 5], dt=dt)
    rf, rl = demod_rim_accel(mu[:, 6], mu[:, 7], mu[:, 11], dt=dt)
    fwd = 0.5 * (lf + rf)
    lat = 0.5 * (ll + rl)
    az_lp = 0.5 * (mu[:, 2] + mu[:, 8])
    az_lp = np.convolve(az_lp.astype(np.float64), np.ones(11) / 11.0, mode="same").astype(np.float32)
    phi_r = np.arcsin(np.clip(rf / g, -1.0, 1.0)).astype(np.float32)
    phi_l = np.arcsin(np.clip(lf / g, -1.0, 1.0)).astype(np.float32)
    phi_mean = np.arcsin(np.clip(fwd / g, -1.0, 1.0)).astype(np.float32)
    phi_abs = np.abs(phi_mean).astype(np.float32)
    pitch = np.arctan2(-fwd, np.maximum(np.abs(az_lp), 1.0)).astype(np.float32)
    grav = np.stack(
        [lf, ll, rf, rl, fwd, lat, az_lp, phi_r, phi_l, phi_mean, phi_abs, pitch],
        axis=-1,
    ).astype(np.float32)
    features = np.concatenate([flat, mu, kin, grav], axis=-1).astype(np.float32)
    if features.shape[1] != BIWHEEL3D_FEATURE_DIM or not np.all(np.isfinite(features)):
        raise ModelInferenceError(f"BiWheel3D feature extraction produced invalid shape {features.shape}.")
    return features


def _load_recipe(path: Path) -> dict[str, Any]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        raise ModelInferenceError(f"Could not read BiWheel3D recipe: {path}") from exc
    if not isinstance(payload, dict) or payload.get("model_type") != "biwheel3d_xy_yaw_recipe":
        raise ModelInferenceError(f"Unsupported BiWheel3D recipe: {path}")
    return payload


def _build_runtime_trial(
    *,
    windows: Any,
    session_data: dict[str, Any],
    Trial: Any,
    TrialMeta: Any,
    np: Any,
    wheel_radius_m: float,
    track_width_m: float,
) -> Any:
    n_steps = int(windows.shape[0])
    n_raw = n_steps * SAMPLES_PER_MODEL_STEP
    left_windows = np.asarray(windows[:, :, :6], dtype=np.float32)
    right_windows = np.asarray(windows[:, :, 6:], dtype=np.float32)
    left_raw = left_windows.reshape(n_raw, 6)
    right_raw = right_windows.reshape(n_raw, 6)

    t_imu = np.arange(n_raw, dtype=np.float64) / float(TARGET_SAMPLE_HZ)
    t_gt = 0.02 + np.arange(n_steps, dtype=np.float64) * 0.05

    session_id = str(session_data.get("session_id") or "wheelathlete_session")
    topic = str(session_data.get("topic") or "")
    maneuver = str(session_data.get("maneuver") or session_data.get("protocol") or "unknown")
    athlete = str(session_data.get("athlete") or "")
    duration_s = float(n_raw / TARGET_SAMPLE_HZ)
    meta = TrialMeta(
        trial_id=session_id,
        split="runtime",
        condition=topic or "runtime",
        maneuver=maneuver,
        R=wheel_radius_m,
        L_hub=track_width_m,
        alpha=0.0,
        L_floor=track_width_m,
        imu_hz=TARGET_SAMPLE_HZ,
        gt_hz=TARGET_SAMPLE_HZ // SAMPLES_PER_MODEL_STEP,
        sync_ratio=SAMPLES_PER_MODEL_STEP,
        duration_s=duration_s,
        n_gt=n_steps,
        n_imu=n_raw,
        has_gt=False,
        athlete=athlete,
    )
    zeros_xyz = np.zeros((n_steps, 3), dtype=np.float32)
    zeros_1d = np.zeros(n_steps, dtype=np.float32)
    return Trial(
        meta=meta,
        t_gt=t_gt,
        xyz=zeros_xyz.copy(),
        xyz_left=zeros_xyz.copy(),
        xyz_right=zeros_xyz.copy(),
        angles=zeros_xyz.copy(),
        v=zeros_1d.copy(),
        omega=zeros_1d.copy(),
        theta_left=zeros_1d.copy(),
        theta_right=zeros_1d.copy(),
        imu_left_windows=left_windows,
        imu_right_windows=right_windows,
        t_imu=t_imu,
        imu_left=left_raw,
        imu_right=right_raw,
    )


def _run_recipe_model(spec: ModelSpec, windows: Any, session_data: dict[str, Any], np: Any) -> dict[str, Any]:
    try:
        from .biwheel3d_runtime.schema import Trial, TrialMeta
        from .biwheel3d_runtime.yaw_ab import (
            DEFAULT_CHASSIS_YAW_SCALE,
            DEFAULT_YAW_DELAY_FRAMES,
            odom_gyro_only,
        )
    except ImportError as exc:
        raise ModelInferenceError("BiWheel3D XY + Yaw runtime could not be imported.") from exc

    recipe = _load_recipe(spec.checkpoint)
    wheel_radius_m = float(recipe.get("wheel_radius_m") or CURRENT_BEST_WHEEL_RADIUS_M)
    track_width_m = float(recipe.get("track_width_m") or CURRENT_BEST_TRACK_WIDTH_M)
    gyro_scale = float(recipe.get("gyro_scale") or 1.10)
    chassis_yaw_scale = float(recipe.get("chassis_yaw_scale") or DEFAULT_CHASSIS_YAW_SCALE)
    yaw_delay_frames = int(recipe.get("yaw_delay_frames", DEFAULT_YAW_DELAY_FRAMES))
    yaw_delay_pad = str(recipe.get("yaw_delay_pad") or "burst")
    yaw_source = str(recipe.get("yaw_source") or "auto")
    align = bool(recipe.get("align", True))
    trial = _build_runtime_trial(
        windows=windows,
        session_data=session_data,
        Trial=Trial,
        TrialMeta=TrialMeta,
        np=np,
        wheel_radius_m=wheel_radius_m,
        track_width_m=track_width_m,
    )
    try:
        pred = odom_gyro_only(
            trial,
            gyro_scale=gyro_scale,
            chassis_yaw_scale=chassis_yaw_scale,
            yaw_delay_frames=yaw_delay_frames,
            yaw_delay_pad=yaw_delay_pad,
            yaw_source=yaw_source,
            align=align,
        )
    except Exception as exc:
        raise ModelInferenceError(f"BiWheel3D XY + Yaw trajectory failed: {exc}") from exc

    xyz = np.asarray(pred.get("xyz"), dtype=np.float64)
    angles = np.asarray(pred.get("angles"), dtype=np.float64)
    if xyz.ndim != 2 or xyz.shape[0] < 2 or xyz.shape[1] < 2 or not np.all(np.isfinite(xyz[:, :2])):
        raise ModelInferenceError("BiWheel3D returned an invalid 2D trajectory.")
    net_yaw_deg: float | None = None
    if angles.ndim == 2 and angles.shape[0] >= 2 and angles.shape[1] >= 2:
        yaw = np.unwrap(angles[:, 1])
        net_yaw_deg = float(np.degrees(yaw[-1] - yaw[0]))
    return {
        "xy": xyz[:, :2],
        "net_yaw_deg": net_yaw_deg,
        "yaw_source": str(pred.get("yaw_source") or yaw_source),
        "yaw_delay_frames": int(pred.get("yaw_delay_frames") or yaw_delay_frames),
        "yaw_delay_pad": str(pred.get("yaw_delay_pad") or yaw_delay_pad),
        "yaw_delay_bursts": int(pred.get("yaw_delay_bursts") or 0),
        "gyro_scale": gyro_scale,
        "chassis_yaw_scale": chassis_yaw_scale,
        "wheel_radius_m": wheel_radius_m,
        "track_width_m": track_width_m,
        "recipe": str(recipe.get("recipe") or spec.label),
        "runtime_source": "biwheel3d_xy_yaw_recipe",
    }


def _run_onnx_model(spec: ModelSpec, windows: Any, np: Any) -> dict[str, Any]:
    try:
        import onnxruntime as ort
        from .biwheel3d_runtime.infer_eval import align_first_travel_xy
    except ImportError as exc:
        raise ModelInferenceError("ONNX Runtime is required to run this model.") from exc

    features = extract_biwheel3d_features(windows)
    try:
        session = ort.InferenceSession(str(spec.checkpoint), providers=["CPUExecutionProvider"])
        inputs = session.get_inputs()
        outputs = session.get_outputs()
        if len(inputs) != 1:
            raise ModelInferenceError("ONNX model must expose exactly one BiWheel3D feature input.")
        input_meta = inputs[0]
        if input_meta.name != "features":
            raise ModelInferenceError(f"ONNX input must be named 'features', got '{input_meta.name}'.")
        if not outputs:
            raise ModelInferenceError("ONNX model exposes no outputs.")
        output_name = "xy" if any(item.name == "xy" for item in outputs) else outputs[0].name
        raw = session.run([output_name], {input_meta.name: features[None, :, :].astype(np.float32)})[0]
    except ModelInferenceError:
        raise
    except Exception as exc:
        raise ModelInferenceError(f"ONNX model inference failed: {exc}") from exc

    xy = np.asarray(raw, dtype=np.float64)
    if xy.ndim == 3 and xy.shape[0] == 1:
        xy = xy[0]
    if xy.ndim != 2 or xy.shape[0] != windows.shape[0] or xy.shape[1] < 2:
        raise ModelInferenceError(f"ONNX model returned unexpected XY shape {xy.shape}.")
    xy = xy[:, :2]
    if not np.all(np.isfinite(xy)):
        raise ModelInferenceError("ONNX model returned non-finite XY values.")
    xyz = np.zeros((xy.shape[0], 3), dtype=np.float32)
    xyz[:, :2] = xy.astype(np.float32)
    aligned_xyz, _ = align_first_travel_xy(xyz, None)
    return {
        "xy": np.asarray(aligned_xyz[:, :2], dtype=np.float64),
        "net_yaw_deg": None,
        "yaw_source": "XY output only",
        "yaw_delay_frames": 0,
        "yaw_delay_pad": "none",
        "yaw_delay_bursts": 0,
        "gyro_scale": None,
        "chassis_yaw_scale": None,
        "wheel_radius_m": CURRENT_BEST_WHEEL_RADIUS_M,
        "track_width_m": CURRENT_BEST_TRACK_WIDTH_M,
        "recipe": "BiWheel3D learned ONNX trajectory model",
        "runtime_source": "onnxruntime_cpu",
        "feature_dim": BIWHEEL3D_FEATURE_DIM,
    }


def run_session_model(
    repo_root: Path,
    spec: ModelSpec,
    session_data: dict[str, Any],
) -> dict[str, Any]:
    """Run one finalized Results recording through the selected local trajectory model."""
    del repo_root
    ready, detail = model_spec_runtime_status(spec)
    if not ready:
        raise ModelInferenceError(detail)
    try:
        import numpy as np
    except ImportError as exc:  # pragma: no cover - guarded above
        raise ModelInferenceError("NumPy is required for trajectory analysis.") from exc

    windows, preprocess = prepare_dual_windows(session_data)
    if spec.kind == "onnx":
        model_result = _run_onnx_model(spec, windows, np)
    elif spec.kind == "recipe":
        model_result = _run_recipe_model(spec, windows, session_data, np)
    else:
        raise ModelInferenceError(f"Unsupported model kind: {spec.kind}")

    xy = np.asarray(model_result.pop("xy"), dtype=np.float64)
    path_length_m = float(np.linalg.norm(np.diff(xy, axis=0), axis=1).sum())
    endpoint_m = float(np.linalg.norm(xy[-1] - xy[0]))
    return {
        "session_id": str(session_data.get("session_id") or ""),
        "topic": str(session_data.get("topic") or ""),
        "trial_number": session_data.get("trial_number", ""),
        "athlete": str(session_data.get("athlete") or ""),
        "model_key": spec.key,
        "model_kind": spec.kind,
        "model_label": spec.label,
        "checkpoint": str(spec.checkpoint),
        "xy": [(float(x), float(y)) for x, y in xy],
        "point_count": int(xy.shape[0]),
        "path_length_m": path_length_m,
        "endpoint_m": endpoint_m,
        "extent_x_m": float(np.ptp(xy[:, 0])),
        "extent_y_m": float(np.ptp(xy[:, 1])),
        "preprocess": preprocess,
        **model_result,
    }
