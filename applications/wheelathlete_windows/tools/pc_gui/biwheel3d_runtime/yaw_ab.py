"""Planar odometry: speed from hub gz, heading from complementary hub yaw."""

from __future__ import annotations

from typing import Any

import numpy as np

from .imu_frame import (
    bin_mean_to_gt,
    canonicalize_dual_windows,
    chassis_yaw_rate_from_hubs,
)
from .infer_eval import align_first_travel_xy, integrate_diffdrive_np
from .schema import Trial

# Hub heading leads mocap after speed-sync (~1.35 s on 10×5 / long slalom).
# Do not drop this until still-start slalom recapture re-measures the lag.
DEFAULT_YAW_DELAY_FRAMES = 27
# 10×5 recipe: five ovals → 10π. Dual-hub ω·â net on 10x5_02 is 1537° at scale 1.
DEFAULT_CHASSIS_YAW_SCALE = 1800.0 / 1537.0
DT_IMU = 0.01
G = 9.80665
STILL_OMEGA_ABS = 0.25
# (ω·a)/g is gravity-valid when |a_xy|≈g; slalom centripetal knocks this off.
CHASSIS_A_REL_TAU = 0.20
CHASSIS_YAW_TAU = 0.80  # rad/s; hard turns prefer wheel-diff
# Below this speed, yaw is treated as in-place (keep chassis).
TRAVEL_V_MIN = 0.50


def dual_mean_channels(trial: Trial) -> dict[str, np.ndarray]:
    """Canonical mean-(T,12) hub channels."""
    w = canonicalize_dual_windows(trial.imu_dual_windows)
    mu = np.asarray(w, dtype=np.float64).mean(axis=1)
    return {
        "mu": mu,
        "omega_l": mu[:, 5],
        "omega_r": mu[:, 11],
        "a_xy": 0.5
        * (
            np.hypot(mu[:, 0], mu[:, 1])
            + np.hypot(mu[:, 6], mu[:, 7])
        ),
    }


def planar_from_dth_dpsi(
    dth: np.ndarray,
    dpsi: np.ndarray,
    *,
    R: float,
    align: bool = True,
) -> tuple[np.ndarray, np.ndarray]:
    """Mid-heading integrate → (angles[T,3], xyz[T,3])."""
    dth = np.asarray(dth, dtype=np.float64).copy()
    dpsi = np.asarray(dpsi, dtype=np.float64).copy()
    dth[0] = 0.0
    dpsi[0] = 0.0
    dangles = np.stack([dth, dpsi, np.zeros_like(dth)], axis=-1).astype(np.float32)
    angles, xyz = integrate_diffdrive_np(dangles, R=float(R))
    if align:
        xyz, angles = align_first_travel_xy(xyz, angles)
        assert angles is not None
    xyz = xyz.copy()
    xyz[:, 2] = 0.0
    return angles.astype(np.float32), xyz.astype(np.float32)


def _causal_shift(x: np.ndarray, k: int, *, pad: str = "zero") -> np.ndarray:
    x = np.asarray(x, dtype=np.float64)
    if k == 0:
        return x
    y = np.zeros_like(x)
    if k > 0:
        y[k:] = x[:-k]
        if pad == "hold":
            y[:k] = x[0]
    else:
        y[:k] = x[-k:]
        if pad == "hold":
            y[k:] = x[-1]
    return y


def first_motion_index(
    dth: np.ndarray,
    dpsi: np.ndarray,
    R: float,
    *,
    path_m: float = 0.002,
    yaw_rad: float = 0.002,
) -> int:
    """First sample that is already moving (idle-trimmed trials → 0)."""
    ds = np.abs(float(R) * np.asarray(dth, dtype=np.float64))
    dy = np.abs(np.asarray(dpsi, dtype=np.float64))
    n = int(min(len(ds), len(dy)))
    if n == 0:
        return 0
    hit = np.flatnonzero((ds[:n] >= float(path_m)) | (dy[:n] >= float(yaw_rad)))
    return int(hit[0]) if hit.size else 0


def shift_heading(
    dpsi: np.ndarray,
    k: int,
    *,
    pad: str,
    motion_i0: int = 0,
) -> np.ndarray:
    """Delay Δψ. ``motion`` keeps pre-travel heading at 0 and hold-pads the rest."""
    dpsi = np.asarray(dpsi, dtype=np.float64)
    k = int(k)
    pad = str(pad)
    if k == 0 or pad in {"", "none"}:
        return dpsi
    if pad == "motion":
        i0 = int(np.clip(motion_i0, 0, max(len(dpsi) - 1, 0)))
        y = np.zeros_like(dpsi)
        y[i0:] = _causal_shift(dpsi[i0:], k, pad="hold")
        return y
    return _causal_shift(dpsi, k, pad=pad)


def shift_heading_bursts(
    dpsi: np.ndarray,
    omega_l: np.ndarray,
    omega_r: np.ndarray,
    k: int,
    *,
    quiet_abs: float = STILL_OMEGA_ABS,
    restart: bool = True,
) -> tuple[np.ndarray, int]:
    """Delay Δψ inside motion bursts. Pauses stay 0; leftover does not leak in.

    ``restart=True`` (live ``burst``): same 1.35 s zero-pad after every ≥1 s
    pause (pause→go treated as a still-start).
    ``restart=False`` (``burst_once``): delay only the first motion burst;
    later bursts apply Δψ immediately so U-turns after a pause are not
    given a fresh heading hole.
    """
    from .pause_segments import debounce_quiet, quiet_mask, runs

    dpsi = np.asarray(dpsi, dtype=np.float64)
    k = int(k)
    if k == 0:
        return dpsi, 1
    n = min(len(dpsi), len(omega_l), len(omega_r))
    quiet = debounce_quiet(quiet_mask(omega_l[:n], omega_r[:n], quiet_abs=quiet_abs))
    out = np.zeros(n, dtype=np.float64)
    n_burst = 0
    for i0, i1, is_quiet in runs(quiet):
        if is_quiet:
            continue
        n_burst += 1
        kk = k if (restart or n_burst == 1) else 0
        out[i0:i1] = _causal_shift(dpsi[i0:i1], kk, pad="zero")
    if n_burst == 0:
        n_burst = 1
        out = _causal_shift(dpsi[:n], k, pad="zero")
    if len(dpsi) > n:
        return np.concatenate([out, dpsi[n:]]), n_burst
    return out, n_burst


def chassis_trust(
    a_xy: np.ndarray,
    yaw_rate: np.ndarray,
    *,
    g: float = G,
    a_rel_tau: float = CHASSIS_A_REL_TAU,
    yaw_tau: float = CHASSIS_YAW_TAU,
    use_yaw: bool = True,
) -> np.ndarray:
    """Weight for (ω·a)/g: ~1 when accel is gravity (and yaw is gentle if ``use_yaw``).

    ``use_yaw=False`` keeps chassis through in-place spins (a≈g, large Δω) and
    hands hard centripetal (slalom) to wheel-diff. The live ``blend`` uses both.
    """
    a_xy = np.asarray(a_xy, dtype=np.float64)
    yaw_rate = np.asarray(yaw_rate, dtype=np.float64)
    a_err = np.abs(a_xy - float(g)) / max(float(g), 1e-9)
    w_a = np.exp(-np.square(a_err / max(float(a_rel_tau), 1e-6)))
    if not use_yaw:
        return np.clip(w_a, 0.0, 1.0)
    w_y = 1.0 / (1.0 + np.square(np.abs(yaw_rate) / max(float(yaw_tau), 1e-6)))
    return np.clip(w_a * w_y, 0.0, 1.0)


def blend_dpsi(
    dpsi_diff: np.ndarray,
    dpsi_chassis: np.ndarray,
    a_xy: np.ndarray,
    *,
    dt: float,
    use_yaw: bool = True,
) -> tuple[np.ndarray, np.ndarray]:
    """Chassis yaw when a≈g; wheel-diff through hard turns (slalom gates)."""
    dpsi_diff = np.asarray(dpsi_diff, dtype=np.float64)
    dpsi_chassis = np.asarray(dpsi_chassis, dtype=np.float64)
    n = min(len(dpsi_diff), len(dpsi_chassis), len(a_xy))
    yaw_rate = dpsi_diff[:n] / max(float(dt), 1e-9)
    w = chassis_trust(a_xy[:n], yaw_rate, use_yaw=use_yaw)
    mixed = w * dpsi_chassis[:n] + (1.0 - w) * dpsi_diff[:n]
    return mixed, w


def blend_travel_dpsi(
    dpsi_diff: np.ndarray,
    dpsi_chassis: np.ndarray,
    v: np.ndarray,
    *,
    dt: float,
    v_min: float = TRAVEL_V_MIN,
    yaw_tau: float = CHASSIS_YAW_TAU,
) -> tuple[np.ndarray, np.ndarray]:
    """Chassis while still/spinning; wheel-diff when translating through a turn.

    Hub |a| stays ≈g on these slaloms, so accel-only blend never hands off.
    Spins have |v| below ``v_min`` and stay on chassis.
    """
    dpsi_diff = np.asarray(dpsi_diff, dtype=np.float64)
    dpsi_chassis = np.asarray(dpsi_chassis, dtype=np.float64)
    v = np.asarray(v, dtype=np.float64)
    n = min(len(dpsi_diff), len(dpsi_chassis), len(v))
    yaw_rate = dpsi_diff[:n] / max(float(dt), 1e-9)
    vmin = max(float(v_min), 1e-6)
    w_v = np.clip((np.abs(v[:n]) - vmin) / vmin, 0.0, 1.0)
    w_y = np.square(np.abs(yaw_rate)) / (
        np.square(np.abs(yaw_rate)) + np.square(max(float(yaw_tau), 1e-6))
    )
    w_diff = np.clip(w_v * w_y, 0.0, 1.0)
    mixed = (1.0 - w_diff) * dpsi_chassis[:n] + w_diff * dpsi_diff[:n]
    return mixed, 1.0 - w_diff


def still_hold_dpsi(
    dpsi: np.ndarray,
    omega_l: np.ndarray,
    omega_r: np.ndarray,
    *,
    quiet_abs: float = STILL_OMEGA_ABS,
) -> np.ndarray:
    """Do not integrate heading while both hubs are quiet."""
    dpsi = np.asarray(dpsi, dtype=np.float64).copy()
    quiet = (np.abs(omega_l) < float(quiet_abs)) & (np.abs(omega_r) < float(quiet_abs))
    n = min(len(dpsi), len(quiet))
    dpsi[:n] = np.where(quiet[:n], 0.0, dpsi[:n])
    return dpsi


def _is_pivot(dth: np.ndarray, dpsi: np.ndarray, R: float) -> bool:
    """In-place spin: lots of heading, little translation (AR/CR)."""
    path = float(np.sum(np.abs(float(R) * dth)))
    yaw = float(np.sum(np.abs(dpsi)))
    return path < 5.0 and yaw > 4.0


def _is_low_yaw_travel(dth: np.ndarray, dpsi: np.ndarray, R: float) -> bool:
    """Sprint / leftover: short path, little heading — do not delay."""
    path = float(np.sum(np.abs(float(R) * dth)))
    yaw = float(np.sum(np.abs(dpsi)))
    return path < 12.0 and yaw < 1.0


def length_omega(
    omega_l: np.ndarray,
    omega_r: np.ndarray,
    *,
    ratio: float = 4.0,
    min_driven_abs: float = 0.5,
    quiet_abs: float = 0.25,
) -> np.ndarray:
    """Common-mode speed, except a quiet hub is not averaged into a one-sided push.

    Spins and 10×5 U-turns keep both hubs moving — leave those on the mean.
    """
    ol = np.asarray(omega_l, dtype=np.float64)
    orr = np.asarray(omega_r, dtype=np.float64)
    al = np.abs(ol)
    ar = np.abs(orr)
    hi = np.maximum(al, ar)
    lo = np.minimum(al, ar)
    driven = np.where(al >= ar, ol, orr)
    mean = 0.5 * (ol + orr)
    one_sided = (
        (hi >= float(min_driven_abs))
        & (lo < float(quiet_abs))
        & (lo * float(ratio) < hi)
    )
    return np.where(one_sided, driven, mean)


def _diff_yaw_dpsi(
    omega_l: np.ndarray,
    omega_r: np.ndarray,
    *,
    R: float,
    L: float,
    dt: float,
    yaw_scale: float,
) -> np.ndarray:
    return float(yaw_scale) * (float(R) / float(L)) * (omega_r - omega_l) * float(dt)


def _chassis_yaw_dpsi(trial: Trial, n: int, dt: float) -> np.ndarray | None:
    left = np.asarray(trial.imu_left, dtype=np.float64)
    right = np.asarray(trial.imu_right, dtype=np.float64)
    if left.ndim != 2 or left.shape[0] < 50 or left.shape[-1] < 6:
        return None
    if right.shape != left.shape:
        return None
    t_gt = np.asarray(trial.t_gt, dtype=np.float64)
    t_imu = np.asarray(trial.t_imu, dtype=np.float64)
    if t_gt.size < 2:
        t_gt = np.arange(n, dtype=np.float64) * float(dt)
    if t_imu.size != len(left):
        t_imu = float(t_gt[0]) + np.arange(len(left), dtype=np.float64) * DT_IMU
    rate = chassis_yaw_rate_from_hubs(left, right, right_lat_sign=1.0)
    y20 = bin_mean_to_gt(rate, t_imu, t_gt[:n], dt_gt=float(dt))
    if len(y20) < n:
        y20 = np.pad(y20, (0, n - len(y20)))
    y20 = y20[:n]
    if not np.isfinite(y20).any():
        return None
    return y20 * float(dt)


def odom_gyro_only(
    trial: Trial,
    *,
    dt: float = 0.05,
    gyro_scale: float = 1.0,
    yaw_scale: float = 1.0,
    yaw_delay_frames: int | None = None,
    yaw_delay_pad: str = "burst",
    yaw_source: str = "auto",
    chassis_yaw_scale: float | None = None,
    still_hold_after: bool = False,
    align: bool = True,
) -> dict[str, Any]:
    """``gz`` common-mode → length. Heading from dual-hub chassis gyro (``ω·â``).

    ``yaw_source``: ``chassis`` / ``diff`` / ``blend`` / ``blend_accel`` /
    ``blend_travel`` / ``auto``.
    ``blend`` also down-weights chassis in hard Δω (rejected on July spins).
    ``blend_accel`` uses |a|≈g only; July slalom |a| stays ≈g so it barely mixes.
    ``blend_travel`` uses wheel-diff when moving and turning (spins stay chassis).
    Travel trials delay Δψ (hubs lead chassis after speed-sync). Pivots and
    low-yaw sprints skip the delay. Default pad is ``burst``: restart the
    delay after each ≥1 s pause so leftover heading does not leak into still.
    ``burst_once`` delays only the first burst (**rejected** on pause U-turns:
    180° pass 58%→3%). Whole-trial ``zero`` / ``motion`` / ``hold`` remain opt-in.
    July bake rejected ``blend`` + motion-pad (test RMSE 0.76 → 1.42 m).
    """
    R = float(trial.meta.R)
    L = float(trial.meta.L_floor)
    ch = dual_mean_channels(trial)
    ls = float(gyro_scale)
    cys = DEFAULT_CHASSIS_YAW_SCALE if chassis_yaw_scale is None else float(chassis_yaw_scale)
    omega_l = ch["omega_l"]
    omega_r = ch["omega_r"]
    mean_both = 0.5 * (omega_l + omega_r)
    dpsi_diff = _diff_yaw_dpsi(omega_l, omega_r, R=R, L=L, dt=dt, yaw_scale=yaw_scale)
    # Full in-place spins (AR/CR) must stay on the mean. A one-stroke can look
    # like a short arc (~few rad) without being a 720° pivot.
    spinish = float(np.sum(np.abs(dpsi_diff))) > 8.0
    mean = mean_both if spinish else length_omega(omega_l, omega_r)
    dth = ls * mean * dt
    src = str(yaw_source)
    used = "diff"
    dpsi = dpsi_diff
    blend_w = np.zeros(len(dth), dtype=np.float64)
    chs = None
    if src in ("chassis", "blend", "blend_accel", "blend_travel", "auto"):
        chs = _chassis_yaw_dpsi(trial, len(dth), dt)
        if chs is not None:
            dpsi_ch = float(cys) * chs
            if src == "blend":
                dpsi, blend_w = blend_dpsi(dpsi_diff, dpsi_ch, ch["a_xy"], dt=dt)
                used = "blend"
            elif src == "blend_accel":
                dpsi, blend_w = blend_dpsi(
                    dpsi_diff, dpsi_ch, ch["a_xy"], dt=dt, use_yaw=False
                )
                used = "blend_accel"
            elif src == "blend_travel":
                v_body = (R * dth) / max(float(dt), 1e-9)
                dpsi, blend_w = blend_travel_dpsi(dpsi_diff, dpsi_ch, v_body, dt=dt)
                used = "blend_travel"
            else:
                dpsi = dpsi_ch
                used = "chassis"
                blend_w = np.ones(len(dth), dtype=np.float64)
        elif src == "chassis":
            dpsi = dpsi_diff
            used = "diff"
    dpsi = still_hold_dpsi(dpsi, omega_l, omega_r)
    k_req = DEFAULT_YAW_DELAY_FRAMES if yaw_delay_frames is None else int(yaw_delay_frames)
    pivot = _is_pivot(dth, dpsi_diff, R)
    applied = 0 if pivot or _is_low_yaw_travel(dth, dpsi_diff, R) else k_req
    pad = str(yaw_delay_pad)
    n_bursts = 1
    if applied != 0:
        if pad == "burst":
            dpsi, n_bursts = shift_heading_bursts(dpsi, omega_l, omega_r, applied)
        elif pad == "burst_once":
            dpsi, n_bursts = shift_heading_bursts(
                dpsi, omega_l, omega_r, applied, restart=False
            )
        else:
            i0 = first_motion_index(dth, dpsi, R)
            dpsi = shift_heading(dpsi, applied, pad=pad, motion_i0=i0)
    else:
        pad = "none"
    if still_hold_after:
        dpsi = still_hold_dpsi(dpsi, omega_l, omega_r)
    angles, xyz = planar_from_dth_dpsi(dth, dpsi, R=R, align=bool(align))
    return {
        "method": "gyro_only",
        "yaw_source": used,
        "xyz": xyz,
        "angles": angles,
        "dth": dth.astype(np.float32),
        "dpsi": dpsi.astype(np.float32),
        "yaw_rate": (dpsi / dt).astype(np.float32),
        "v": (R * dth / dt).astype(np.float32),
        "channels": ch,
        "gyro_scale": ls,
        "yaw_scale": float(yaw_scale),
        "chassis_yaw_scale": float(cys) if used in ("chassis", "blend", "blend_accel", "blend_travel") else 1.0,
        "yaw_delay_frames": int(applied),
        "yaw_delay_pad": pad,
        "yaw_delay_bursts": int(n_bursts),
        "pivot": bool(pivot),
        "blend_chassis_frac": float(np.mean(blend_w)) if len(blend_w) else 0.0,
        "one_sided_frac": float(
            np.mean(
                (np.maximum(np.abs(omega_l), np.abs(omega_r)) >= 0.5)
                & (np.minimum(np.abs(omega_l), np.abs(omega_r)) < 0.25)
                & (
                    np.minimum(np.abs(omega_l), np.abs(omega_r)) * 4.0
                    < np.maximum(np.abs(omega_l), np.abs(omega_r))
                )
            )
        ),
    }
