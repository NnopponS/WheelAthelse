from __future__ import annotations

import importlib.util
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any


ACCEL_G_TO_MS2 = 9.80665
TARGET_SAMPLE_HZ = 100
SAMPLES_PER_MODEL_STEP = 5
MIN_MODEL_STEPS = 40
CURRENT_BEST_WHEEL_RADIUS_M = 0.30
CURRENT_BEST_TRACK_WIDTH_M = 0.52
CURRENT_BEST_KEY = "biwheel3d:xy_yaw_current_best"


class ModelInferenceError(RuntimeError):
    """Raised when a recording cannot be prepared or the trajectory method cannot run safely."""


@dataclass(frozen=True, slots=True)
class ModelSpec:
    key: str
    label: str
    checkpoint: Path
    description: str


def custom_model_spec(checkpoint: Path) -> ModelSpec:
    """Compatibility helper for older callers; legacy checkpoints are no longer the default runtime."""
    resolved = checkpoint.expanduser().resolve()
    return ModelSpec(
        key=f"custom:{resolved}",
        label=f"Legacy checkpoint - {resolved.stem}",
        checkpoint=resolved,
        description=(
            "Legacy PyTorch checkpoint selection. The current BiWheel3D tree no longer ships the old "
            "TCN + BiLSTM stack, so this path is not supported by the current MODEL runtime."
        ),
    )


def _runtime_root() -> Path:
    return Path(__file__).resolve().parent / "biwheel3d_runtime"


def _current_best_summary(repo_root: Path | None = None) -> Path:
    del repo_root
    return _runtime_root() / "current_best_summary.json"


def discover_compatible_models(repo_root: Path) -> list[ModelSpec]:
    """Discover the bundled BiWheel3D planar XY + yaw recipe."""
    del repo_root
    summary = _current_best_summary()
    yaw_impl = _runtime_root() / "yaw_ab.py"
    if not summary.is_file() or not yaw_impl.is_file():
        return []
    return [
        ModelSpec(
            key=CURRENT_BEST_KEY,
            label="BiWheel3D XY + Yaw - current_best",
            checkpoint=summary,
            description=(
                "Current BiWheel3D v0.3 planar estimator: wheel speed from dual hub gz, "
                "dual-hub chassis yaw, and 27-frame burst-delay handling after pauses."
            ),
        )
    ]


def model_runtime_status(repo_root: Path) -> tuple[bool, str]:
    """Check the self-contained current BiWheel3D runtime without importing it."""
    del repo_root
    if importlib.util.find_spec("numpy") is None:
        return False, "NumPy is required for BiWheel3D XY + Yaw."
    runtime = _runtime_root()
    if not (runtime / "yaw_ab.py").is_file():
        return False, "Bundled BiWheel3D XY + Yaw runtime is missing."
    if not _current_best_summary().is_file():
        return False, "Bundled BiWheel3D current_best calibration is missing."
    return True, "Bundled BiWheel3D XY + Yaw current_best is ready (CPU, no PyTorch or external checkout required)."


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


def _load_current_best_recipe(repo_root: Path) -> dict[str, Any]:
    summary_path = _current_best_summary(repo_root)
    try:
        summary = json.loads(summary_path.read_text(encoding="utf-8"))
    except Exception as exc:
        raise ModelInferenceError(f"Could not read BiWheel3D current_best recipe: {summary_path}") from exc
    if not isinstance(summary, dict):
        raise ModelInferenceError("BiWheel3D current_best summary is invalid.")
    return summary


def _build_runtime_trial(
    *,
    windows: Any,
    session_data: dict[str, Any],
    Trial: Any,
    TrialMeta: Any,
    np: Any,
) -> Any:
    n_steps = int(windows.shape[0])
    n_raw = n_steps * SAMPLES_PER_MODEL_STEP
    left_windows = np.asarray(windows[:, :, :6], dtype=np.float32)
    right_windows = np.asarray(windows[:, :, 6:], dtype=np.float32)
    left_raw = left_windows.reshape(n_raw, 6)
    right_raw = right_windows.reshape(n_raw, 6)

    # BiWheel3D processed trials use the 20 Hz sample at the center of each 5x100 Hz window.
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
        R=CURRENT_BEST_WHEEL_RADIUS_M,
        L_hub=CURRENT_BEST_TRACK_WIDTH_M,
        alpha=0.0,
        L_floor=CURRENT_BEST_TRACK_WIDTH_M,
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


def run_session_model(
    repo_root: Path,
    spec: ModelSpec,
    session_data: dict[str, Any],
) -> dict[str, Any]:
    """Run one finalized Results recording through BiWheel3D current_best XY + yaw."""
    ready, detail = model_runtime_status(repo_root)
    if not ready:
        raise ModelInferenceError(detail)
    if spec.key != CURRENT_BEST_KEY:
        raise ModelInferenceError(
            "This WheelAthlete build supports the current BiWheel3D XY + Yaw recipe only. "
            "The old TCN + BiLSTM checkpoint stack is not part of the bundled current runtime."
        )

    try:
        import numpy as np
        from .biwheel3d_runtime.schema import Trial, TrialMeta
        from .biwheel3d_runtime.yaw_ab import (
            DEFAULT_CHASSIS_YAW_SCALE,
            DEFAULT_YAW_DELAY_FRAMES,
            odom_gyro_only,
        )
    except ImportError as exc:
        raise ModelInferenceError(
            "BiWheel3D current_best runtime could not be imported. Ensure NumPy is installed and BiWheel3D is present."
        ) from exc

    windows, preprocess = prepare_dual_windows(session_data)
    trial = _build_runtime_trial(
        windows=windows,
        session_data=session_data,
        Trial=Trial,
        TrialMeta=TrialMeta,
        np=np,
    )
    recipe = _load_current_best_recipe(repo_root)
    gyro_scale = float(recipe.get("gyro_scale") or 1.10)
    chassis_yaw_scale = float(recipe.get("chassis_yaw_scale") or DEFAULT_CHASSIS_YAW_SCALE)

    try:
        pred = odom_gyro_only(
            trial,
            gyro_scale=gyro_scale,
            chassis_yaw_scale=chassis_yaw_scale,
            yaw_delay_frames=int(DEFAULT_YAW_DELAY_FRAMES),
            yaw_delay_pad="burst",
            yaw_source="auto",
            align=True,
        )
    except Exception as exc:
        raise ModelInferenceError(f"BiWheel3D current_best trajectory failed: {exc}") from exc

    xyz = np.asarray(pred.get("xyz"), dtype=np.float64)
    angles = np.asarray(pred.get("angles"), dtype=np.float64)
    if xyz.ndim != 2 or xyz.shape[0] < 2 or xyz.shape[1] < 2 or not np.all(np.isfinite(xyz[:, :2])):
        raise ModelInferenceError("BiWheel3D returned an invalid 2D trajectory.")
    xy = xyz[:, :2]
    path_length_m = float(np.linalg.norm(np.diff(xy, axis=0), axis=1).sum())
    endpoint_m = float(np.linalg.norm(xy[-1] - xy[0]))
    extent_x = float(np.ptp(xy[:, 0]))
    extent_y = float(np.ptp(xy[:, 1]))

    net_yaw_deg = 0.0
    if angles.ndim == 2 and angles.shape[0] >= 2 and angles.shape[1] >= 2:
        yaw = np.unwrap(angles[:, 1])
        net_yaw_deg = float(np.degrees(yaw[-1] - yaw[0]))

    return {
        "session_id": str(session_data.get("session_id") or ""),
        "topic": str(session_data.get("topic") or ""),
        "trial_number": session_data.get("trial_number", ""),
        "athlete": str(session_data.get("athlete") or ""),
        "model_key": spec.key,
        "model_label": spec.label,
        "checkpoint": str(spec.checkpoint),
        "recipe": str(recipe.get("recipe") or "BiWheel3D current_best"),
        "xy": [(float(x), float(y)) for x, y in xy],
        "point_count": int(xy.shape[0]),
        "path_length_m": path_length_m,
        "endpoint_m": endpoint_m,
        "extent_x_m": extent_x,
        "extent_y_m": extent_y,
        "net_yaw_deg": net_yaw_deg,
        "yaw_source": str(pred.get("yaw_source") or ""),
        "yaw_delay_frames": int(pred.get("yaw_delay_frames") or 0),
        "yaw_delay_pad": str(pred.get("yaw_delay_pad") or "none"),
        "yaw_delay_bursts": int(pred.get("yaw_delay_bursts") or 0),
        "gyro_scale": gyro_scale,
        "chassis_yaw_scale": chassis_yaw_scale,
        "wheel_radius_m": CURRENT_BEST_WHEEL_RADIUS_M,
        "track_width_m": CURRENT_BEST_TRACK_WIDTH_M,
        "runtime_source": "bundled_biwheel3d_v0.3.0",
        "preprocess": preprocess,
    }
