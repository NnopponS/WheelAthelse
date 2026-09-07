"""Planar path helpers: alignment, diff-drive integration, spin scoring."""

from __future__ import annotations

import numpy as np

SPIN_MANEUVERS = ("turn_left", "turn_right")
ONE_STROKE_MANEUVERS = ("one_stroke", "one_st")
SPIN_TARGET_RAD = 4.0 * np.pi  # 720°
SPIN_DETECT_RAD = 1.5 * 2.0 * np.pi  # ≥1.5 turns counts as detected


def is_spin_maneuver(maneuver: str | None) -> bool:
    return str(maneuver or "") in SPIN_MANEUVERS


def is_one_stroke_maneuver(maneuver: str | None) -> bool:
    """OWC / 1ST: one wheel pushed, the other planted — an arc, not a sprint."""
    return str(maneuver or "") in ONE_STROKE_MANEUVERS


def align_axle_heading_xy(
    xyz: np.ndarray,
    angles: np.ndarray | None = None,
) -> tuple[np.ndarray, np.ndarray | None]:
    """Origin-reset and rotate so initial axle heading is 0 (no first-travel +x)."""
    xyz = np.asarray(xyz, dtype=np.float64).copy()
    xyz = xyz - xyz[0]
    out_ang = None
    yaw0 = 0.0
    if angles is not None:
        out_ang = np.asarray(angles, dtype=np.float64).copy()
        yaw0 = float(out_ang[0, 1])
        out_ang[:, 1] = out_ang[:, 1] - yaw0
        out_ang = out_ang.astype(np.float32)
    c, s = np.cos(-yaw0), np.sin(-yaw0)
    rot = np.array([[c, -s, 0.0], [s, c, 0.0], [0.0, 0.0, 1.0]])
    xyz = (rot @ xyz.T).T
    return xyz.astype(np.float32), out_ang


def heading_pattern_metrics(
    gt_angles: np.ndarray,
    pred_angles: np.ndarray,
    *,
    dt: float = 0.05,
    first_turn_deg: float = 20.0,
) -> dict[str, float | bool]:
    """Pattern-level heading scores (sign, timing, heading RMSE) — not XY overlay."""
    gt = np.unwrap(np.asarray(gt_angles, dtype=np.float64)[:, 1])
    pr = np.unwrap(np.asarray(pred_angles, dtype=np.float64)[:, 1])
    n = min(len(gt), len(pr))
    gt, pr = gt[:n] - gt[0], pr[:n] - pr[0]
    gt_net = float(gt[-1])
    pr_net = float(pr[-1])
    quiet = max(abs(gt_net), abs(pr_net)) < np.radians(15.0)
    sign_match = bool(quiet or np.sign(gt_net) == np.sign(pr_net))
    err = np.degrees(gt - pr)
    rmse_deg = float(np.sqrt(np.mean(err**2)))

    def _first_turn_s(psi: np.ndarray) -> float:
        mag = np.abs(np.degrees(psi))
        hit = np.flatnonzero(mag >= float(first_turn_deg))
        if hit.size == 0:
            return float("nan")
        return float(hit[0]) * float(dt)

    t_gt = _first_turn_s(gt)
    t_pr = _first_turn_s(pr)
    first_err = (
        float(t_pr - t_gt) if np.isfinite(t_gt) and np.isfinite(t_pr) else float("nan")
    )
    return {
        "gt_net_deg": float(np.degrees(gt_net)),
        "pred_net_deg": float(np.degrees(pr_net)),
        "net_err_deg": float(abs(np.degrees(pr_net - gt_net))),
        "sign_match": sign_match,
        "rmse_heading_deg": rmse_deg,
        "first_turn_gt_s": t_gt,
        "first_turn_pred_s": t_pr,
        "first_turn_err_s": first_err,
    }


def spin_heading_metrics(
    gt_angles: np.ndarray,
    pred_angles: np.ndarray,
    *,
    target_rad: float = SPIN_TARGET_RAD,
    detect_rad: float = SPIN_DETECT_RAD,
) -> dict[str, float | bool]:
    """Score a ~720° spin by unwrapped net yaw, not XY drift."""
    gt = np.unwrap(np.asarray(gt_angles, dtype=np.float64)[:, 1])
    pr = np.unwrap(np.asarray(pred_angles, dtype=np.float64)[:, 1])
    gt_net = float(gt[-1] - gt[0])
    pr_net = float(pr[-1] - pr[0])
    tgt = float(np.sign(gt_net) * abs(target_rad)) if abs(gt_net) > 0.5 else float(target_rad)
    return {
        "gt_net_rad": gt_net,
        "pred_net_rad": pr_net,
        "gt_deg": float(np.degrees(gt_net)),
        "pred_deg": float(np.degrees(pr_net)),
        "target_deg": float(np.degrees(tgt)),
        "abs_err_deg": float(abs(np.degrees(pr_net - gt_net))),
        "target_err_deg": float(abs(np.degrees(pr_net - tgt))),
        "detected_1p5_turns": bool(abs(pr_net) >= float(detect_rad)),
    }


def align_first_travel_xy(
    xyz: np.ndarray,
    angles: np.ndarray | None = None,
    *,
    dist_m: float = 0.30,
) -> tuple[np.ndarray, np.ndarray | None]:
    """Rotate planar path so the first ``dist_m`` of travel lies along +x."""
    xyz = np.asarray(xyz, dtype=np.float64).copy()
    xyz = xyz - xyz[0]
    ds = np.linalg.norm(np.diff(xyz[:, :2], axis=0, prepend=xyz[:1, :2]), axis=1)
    ds[0] = 0.0
    cum = np.cumsum(ds)
    j = int(np.searchsorted(cum, dist_m))
    j = int(np.clip(j, 1, len(xyz) - 1))
    travel = xyz[j, :2] - xyz[0, :2]
    if float(np.hypot(travel[0], travel[1])) < 0.05:
        travel = xyz[min(20, len(xyz) - 1), :2] - xyz[0, :2]
    yaw0 = float(np.arctan2(travel[1], travel[0]))
    c, s = np.cos(-yaw0), np.sin(-yaw0)
    rot = np.array([[c, -s, 0.0], [s, c, 0.0], [0.0, 0.0, 1.0]])
    xyz = (rot @ xyz.T).T
    out_ang = None
    if angles is not None:
        out_ang = np.asarray(angles, dtype=np.float64).copy()
        out_ang[:, 1] = out_ang[:, 1] - yaw0
        out_ang[:, 1] = out_ang[:, 1] - out_ang[0, 1]
        out_ang = out_ang.astype(np.float32)
    return xyz.astype(np.float32), out_ang


def integrate_diffdrive_np(
    dangles: np.ndarray,
    *,
    R: float = 0.30,
    phi_abs_clip: float = 0.60,
) -> tuple[np.ndarray, np.ndarray]:
    """Mid-heading integration from [Δθ, Δψ, Δφ] → (angles, xyz); Z via tan(φ)."""
    d = np.asarray(dangles, dtype=np.float64)
    dth = d[:, 0]
    dpsi = d[:, 1]
    dphi = d[:, 2]
    psi = np.cumsum(dpsi)
    psi = psi - psi[0]
    mid = psi - 0.5 * dpsi
    ds = float(R) * dth
    dx = ds * np.cos(mid)
    dy = ds * np.sin(mid)
    phi = np.cumsum(dphi)
    phi = phi - phi[0]
    phi_c = np.clip(phi, -float(phi_abs_clip), float(phi_abs_clip))
    dz = ds * np.tan(phi_c)
    xyz = np.zeros((len(d), 3), dtype=np.float64)
    xyz[:, 0] = np.cumsum(dx)
    xyz[:, 1] = np.cumsum(dy)
    xyz[:, 2] = np.cumsum(dz)
    theta = np.cumsum(dth)
    theta = theta - theta[0]
    angles = np.stack([theta, psi, phi], axis=-1)
    return angles.astype(np.float32), xyz.astype(np.float32)
