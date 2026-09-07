"""IMU frame conventions (WheelSense hub mounts).

Lab data: left/right hubs are mirrored. We canonicalize the right IMU so:

- positive ``gz`` = forward-driving spin
- lateral axes (ay, gy) are mirrored into the left-wheel sense
- speed ``v ≈ R/2 (ω_L+ω_R)``, yaw ``ψ̇ ≈ (R/L)(ω_R−ω_L)``

Channel order per wheel: ``[ax, ay, az, gx, gy, gz]``.
"""

from __future__ import annotations

import numpy as np

# Right-wheel sign flips into left-wheel convention.
# Empirically only gz must flip for diff-drive; ay/gy left unflipped so rim
# demod (Rxy) keeps its ~0.5 corr with path incline on ramp trials.
RIGHT_GZ_SIGN = -1.0
RIGHT_AY_SIGN = 1.0
RIGHT_GY_SIGN = 1.0


def canonicalize_right_imu(imu_right: np.ndarray) -> np.ndarray:
    """Copy with right lateral + gz flipped into the left-wheel convention."""
    out = np.asarray(imu_right, dtype=np.float32).copy()
    if out.ndim != 2 or out.shape[-1] < 6:
        raise ValueError(f"expected (T,6+) right IMU, got {out.shape}")
    out[:, 1] *= float(RIGHT_AY_SIGN)  # ay
    out[:, 4] *= float(RIGHT_GY_SIGN)  # gy
    out[:, 5] *= float(RIGHT_GZ_SIGN)  # gz
    return out


def canonicalize_dual_windows(imu_dual_windows: np.ndarray) -> np.ndarray:
    """Flip right lateral + gz in dual windows ``(T, 5, 12)``."""
    w = np.asarray(imu_dual_windows, dtype=np.float32).copy()
    if w.ndim != 3 or w.shape[-1] != 12:
        raise ValueError(f"expected (T,5,12), got {w.shape}")
    w[:, :, 7] *= float(RIGHT_AY_SIGN)  # ray
    w[:, :, 10] *= float(RIGHT_GY_SIGN)  # rgy
    w[:, :, 11] *= float(RIGHT_GZ_SIGN)  # rgz
    return w


def wheel_spin_rates_from_mean12(mu12: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """``(ω_L, ω_R)`` from already-canonical mean dual IMU ``(T, 12)``."""
    mu = np.asarray(mu12, dtype=np.float32)
    return mu[:, 5], mu[:, 11]


def demod_rim_xy(
    x: np.ndarray,
    y: np.ndarray,
    gz: np.ndarray,
    *,
    dt: float = 0.05,
    lp_win: int = 21,
) -> tuple[np.ndarray, np.ndarray]:
    """Rotate rim-plane (x, y) by integrated gz → quasi-body frame, then low-pass.

    Hub xy spins with the wheel. Undoing gz isolates slowly varying chair-frame
    cues (accel incline, or chassis yaw in gx/gy).
    """
    x = np.asarray(x, dtype=np.float64)
    y = np.asarray(y, dtype=np.float64)
    gz = np.asarray(gz, dtype=np.float64)
    th = np.cumsum(gz * float(dt))
    th = th - th[0]
    c, s = np.cos(-th), np.sin(-th)
    fwd = x * c - y * s
    lat = x * s + y * c
    k = max(3, int(lp_win) | 1)
    ker = np.ones(k, dtype=np.float64) / k
    return (
        np.convolve(fwd, ker, mode="same").astype(np.float32),
        np.convolve(lat, ker, mode="same").astype(np.float32),
    )


def demod_rim_accel(
    ax: np.ndarray,
    ay: np.ndarray,
    gz: np.ndarray,
    *,
    dt: float = 0.05,
    lp_win: int = 21,
) -> tuple[np.ndarray, np.ndarray]:
    """Rotate rim-plane accel by integrated gz → quasi-body frame, then low-pass.

    Returns ``(a_fwd_lp, a_lat_lp)``. Correlates with path incline on ramp trials.
    """
    return demod_rim_xy(ax, ay, gz, dt=dt, lp_win=lp_win)


def demod_rim_gyro(
    gx: np.ndarray,
    gy: np.ndarray,
    gz: np.ndarray,
    *,
    dt: float = 0.05,
    lp_win: int = 11,
) -> tuple[np.ndarray, np.ndarray]:
    """Wheel-plane gyro demodulated by spin → quasi-body ``(g_fwd, g_lat)`` rad/s.

    Chassis yaw about vertical lives in gx/gy (gz is wheel spin). Shorter LP
    than accel so U-turn edges are not smeared.
    """
    return demod_rim_xy(gx, gy, gz, dt=dt, lp_win=lp_win)


def _lp(x: np.ndarray, win: int) -> np.ndarray:
    k = max(3, int(win) | 1)
    ker = np.ones(k, dtype=np.float64) / k
    return np.convolve(np.asarray(x, dtype=np.float64), ker, mode="same")


def vertical_gyro_from_rim(
    gx: np.ndarray,
    gy: np.ndarray,
    ax: np.ndarray,
    ay: np.ndarray,
) -> np.ndarray:
    """Wheel-plane gyro along rim accel / g — spin-invariant chassis yaw (rad/s).

    World-Z lies in the wheel plane (camber 0). ``(ω_xy · a_xy) / g`` does not
    need ``∫gz``.
    """
    gx = np.asarray(gx, dtype=np.float64)
    gy = np.asarray(gy, dtype=np.float64)
    ax = np.asarray(ax, dtype=np.float64)
    ay = np.asarray(ay, dtype=np.float64)
    return (gx * ax + gy * ay) / 9.80665


def phase_lock_wheel_angle(
    ax: np.ndarray,
    ay: np.ndarray,
    gz: np.ndarray,
    *,
    dt: float,
    lp_win: int = 101,
) -> np.ndarray:
    """θ = ∫gz plus slow gravity-harmonic phase (corrects gz scale drift)."""
    gz = np.asarray(gz, dtype=np.float64)
    ax = np.asarray(ax, dtype=np.float64)
    ay = np.asarray(ay, dtype=np.float64)
    th = np.cumsum(gz * float(dt))
    th = th - th[0]
    z = ax + 1.0j * ay
    bb = z * np.exp(-1.0j * th)
    bb_lp = _lp(bb.real, lp_win) + 1.0j * _lp(bb.imag, lp_win)
    phi = np.angle(bb_lp)
    return th + phi


def demod_phase_locked(
    gx: np.ndarray,
    gy: np.ndarray,
    ax: np.ndarray,
    ay: np.ndarray,
    gz: np.ndarray,
    *,
    dt: float,
    lp_win: int = 11,
) -> tuple[np.ndarray, np.ndarray]:
    """Rotate rim gyro by gravity-locked wheel angle → quasi-body (fwd, lat)."""
    th = phase_lock_wheel_angle(ax, ay, gz, dt=dt)
    c, s = np.cos(-th), np.sin(-th)
    gx = np.asarray(gx, dtype=np.float64)
    gy = np.asarray(gy, dtype=np.float64)
    fwd = gx * c - gy * s
    lat = gx * s + gy * c
    return _lp(fwd, lp_win).astype(np.float32), _lp(lat, lp_win).astype(np.float32)


def chassis_yaw_rate_from_hubs(
    imu_left: np.ndarray,
    imu_right: np.ndarray,
    *,
    right_lat_sign: float = 1.0,
    lp_win: int = 11,
) -> np.ndarray:
    """Dual-hub chassis yaw (rad/s) from rim gyro along gravity.

    Uses full-rate SI IMU ``(N, 6)``. Right is canonicalized. Returns left/right
    average, low-passed.
    """
    left = np.asarray(imu_left, dtype=np.float64)
    right = canonicalize_right_imu(np.asarray(imu_right, dtype=np.float64)).astype(np.float64)
    yl = vertical_gyro_from_rim(left[:, 3], left[:, 4], left[:, 0], left[:, 1])
    yr = vertical_gyro_from_rim(right[:, 3], right[:, 4], right[:, 0], right[:, 1])
    y = 0.5 * (yl + float(right_lat_sign) * yr)
    return _lp(y, lp_win).astype(np.float32)


def bin_mean_to_gt(
    x100: np.ndarray,
    t_imu: np.ndarray,
    t_gt: np.ndarray,
    *,
    dt_gt: float = 0.05,
) -> np.ndarray:
    """Mean 100 Hz samples into each 20 Hz GT bin."""
    x100 = np.asarray(x100, dtype=np.float64)
    t_imu = np.asarray(t_imu, dtype=np.float64)
    t_gt = np.asarray(t_gt, dtype=np.float64)
    out = np.full(len(t_gt), np.nan, dtype=np.float64)
    half = 0.5 * float(dt_gt)
    idx = np.searchsorted(t_imu, t_gt - half, side="left")
    idx_r = np.searchsorted(t_imu, t_gt + half, side="left")
    for i, (a, b) in enumerate(zip(idx, idx_r)):
        if b > a:
            out[i] = float(np.mean(x100[a:b]))
    bad = ~np.isfinite(out)
    if bad.any() and (~bad).any():
        out[bad] = np.interp(t_gt[bad], t_gt[~bad], out[~bad])
    elif bad.any():
        out[bad] = 0.0
    return out
