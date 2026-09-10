"""Deterministic train-calibrated fixed-course Slalom adapter v3.

Residual-v1 network weights stay frozen. Two tiny linear calibrators correct the
predicted yaw-rate and signed-speed waveforms using only quantities available at
inference. A sign-aware course detector then applies the declared start/end
heading constraint and a guarded minimum-norm position closure for complete
courses. No C3D is read at inference.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Any

import numpy as np

from .slalom_course import DT, _close_position, integrate_rates_float32


@dataclass(frozen=True)
class SlalomCalibratedV3Result:
    rates: np.ndarray
    applied: bool
    complete_course: bool
    reason: str
    turn_count: int
    major_turn_count: int
    major_sign_pattern: tuple[int, ...]
    heading_closure: bool
    position_closure: bool
    raw_net_heading_deg: float
    calibrated_net_heading_deg: float
    final_net_heading_deg: float
    calibration_applied: bool
    calibration_reason: str
    yaw_calibration_rms_degps: float
    yaw_calibration_max_abs_degps: float
    speed_calibration_rms_mps: float
    speed_calibration_max_abs_mps: float
    heading_removed_deg: float
    closure_speed_correction_rms_mps: float
    closure_speed_correction_max_abs_mps: float
    closure_speed_correction_rms_fraction_median: float
    closure_speed_correction_max_fraction_median: float
    median_moving_speed_mps: float
    endpoint_before_m: float
    endpoint_after_calibration_m: float
    endpoint_after_heading_m: float
    endpoint_after_m: float


def detect_turn_events_sign_aware(
    yaw_rate_radps: np.ndarray,
    *, threshold_degps: float = 20.0,
    merge_gap_frames: int = 10,
    min_event_frames: int = 8,
) -> list[tuple[int, int]]:
    w = np.asarray(yaw_rate_radps, dtype=float)
    if w.ndim != 1 or not np.isfinite(w).all():
        raise ValueError("yaw rate must be a finite one-dimensional array")
    active = np.abs(w) > np.deg2rad(float(threshold_degps))
    edges = np.diff(np.r_[False, active, False].astype(np.int8))
    raw = list(zip(np.flatnonzero(edges == 1).tolist(), np.flatnonzero(edges == -1).tolist()))
    merged: list[list[int]] = []
    for start, stop in raw:
        sign = 1 if float(np.sum(w[start:stop])) >= 0 else -1
        if merged and merged[-1][2] == sign and start - merged[-1][1] <= int(merge_gap_frames):
            merged[-1][1] = stop
        else:
            merged.append([start, stop, sign])
    return [(a, z) for a, z, _ in merged if z - a >= int(min_event_frames)]


def _midpoint_integral(v: np.ndarray, dt: float = DT) -> float:
    x = np.asarray(v, dtype=float)
    if len(x) < 2:
        return 0.0
    return float(np.sum(0.5 * (x[1:] + x[:-1])) * float(dt))


def _event_delta_deg(w: np.ndarray, event: tuple[int, int], dt: float = DT) -> float:
    a, z = event
    return float(np.degrees(np.sum(np.asarray(w, dtype=float)[a:z]) * float(dt)))


def major_turn_pattern(
    yaw_rate_radps: np.ndarray,
    events: list[tuple[int, int]],
    *, min_abs_turn_deg: float = 60.0,
    dt: float = DT,
) -> tuple[int, ...]:
    out: list[int] = []
    for event in events:
        d = _event_delta_deg(yaw_rate_radps, event, dt=dt)
        if abs(d) >= float(min_abs_turn_deg):
            out.append(1 if d >= 0 else -1)
    return tuple(out)


def yaw_features(
    predicted_rates: np.ndarray,
    research_rates: np.ndarray,
    *, dt: float = DT,
) -> np.ndarray:
    p = np.asarray(predicted_rates, dtype=float)
    r = np.asarray(research_rates, dtype=float)
    if p.shape != r.shape or p.ndim != 2 or p.shape[1] != 2:
        raise ValueError("predicted/research rates must share finite (T,2) shape")
    if not np.isfinite(p).all() or not np.isfinite(r).all():
        raise ValueError("calibrator rates must be finite")
    w = p[:, 1]
    ph = r[:, 1]
    v = p[:, 0]
    dw = np.gradient(w, float(dt))
    dph = np.gradient(ph, float(dt))
    diff = ph - w
    return np.column_stack([
        np.ones(len(w)), diff, v, np.abs(w), np.sign(w), dw, dph,
        w * v, np.abs(diff), np.sign(w) * diff,
    ])


def speed_features(
    predicted_rates: np.ndarray,
    research_rates: np.ndarray,
    current_rates: np.ndarray,
    *, dt: float = DT,
) -> np.ndarray:
    p = np.asarray(predicted_rates, dtype=float)
    r = np.asarray(research_rates, dtype=float)
    c = np.asarray(current_rates, dtype=float)
    if p.shape != r.shape or p.shape != c.shape or p.ndim != 2 or p.shape[1] != 2:
        raise ValueError("speed calibrator rates must share (T,2) shape")
    v = p[:, 0]
    w = np.abs(p[:, 1])
    dv = np.gradient(v, float(dt))
    return np.column_stack([
        np.ones(len(v)), r[:, 0] - v, c[:, 0] - v, v, np.abs(v),
        np.sign(v), w, dv, v * w,
    ])


def apply_linear_calibration(
    predicted_rates: np.ndarray,
    research_rates: np.ndarray,
    current_rates: np.ndarray,
    calibration: dict[str, Any],
    *, dt: float = DT,
) -> tuple[np.ndarray, dict[str, float]]:
    p = np.asarray(predicted_rates, dtype=np.float32)
    out = p.copy()
    yaw_beta = np.asarray(calibration["yaw_residual_coefficients"], dtype=float)
    speed_beta = np.asarray(calibration["speed_residual_coefficients"], dtype=float)
    yf = yaw_features(p, research_rates, dt=dt)
    sf = speed_features(p, research_rates, current_rates, dt=dt)
    if yaw_beta.shape != (yf.shape[1],) or speed_beta.shape != (sf.shape[1],):
        raise ValueError("Slalom v3 calibrator coefficient shape mismatch")
    yd = yf @ yaw_beta
    sd = sf @ speed_beta
    max_yaw = float(calibration.get("max_abs_yaw_calibration_degps", 5.0))
    max_speed = float(calibration.get("max_abs_speed_calibration_mps", 0.05))
    yaw_rms = float(np.sqrt(np.mean(np.degrees(yd) ** 2)))
    yaw_max = float(np.max(np.abs(np.degrees(yd)), initial=0.0))
    speed_rms = float(np.sqrt(np.mean(sd ** 2)))
    speed_max = float(np.max(np.abs(sd), initial=0.0))
    guard_ok = yaw_max <= max_yaw + 1e-9 and speed_max <= max_speed + 1e-9
    if guard_ok:
        out[:, 1] = (p[:, 1].astype(float) + yd).astype(np.float32)
        out[:, 0] = (p[:, 0].astype(float) + sd).astype(np.float32)
    return out, {
        "calibration_applied": bool(guard_ok),
        "calibration_reason": "within_training_envelope" if guard_ok else "guard_exceeded_fallback_to_raw_v1",
        "yaw_calibration_rms_degps": yaw_rms,
        "yaw_calibration_max_abs_degps": yaw_max,
        "speed_calibration_rms_mps": speed_rms,
        "speed_calibration_max_abs_mps": speed_max,
    }


def _close_heading_equal(
    rates: np.ndarray,
    events: list[tuple[int, int]],
    expected_net_heading_rad: float,
    *, dt: float = DT,
) -> tuple[np.ndarray, float]:
    out = np.asarray(rates, dtype=np.float32).copy()
    if not events:
        return out, 0.0
    net = _midpoint_integral(out[:, 1], dt=dt)
    error = net - float(expected_net_heading_rad)
    weights = np.zeros(len(out), dtype=float)
    for a, z in events:
        weights[a:z] = 1.0 / float(z - a)
    integ = _midpoint_integral(weights, dt=dt)
    if integ <= 1e-12:
        return out, 0.0
    out[:, 1] = (out[:, 1].astype(float) - error * weights / integ).astype(np.float32)
    return out, float(np.degrees(error))


def apply_slalom_calibrated_v3(
    predicted_rates: np.ndarray,
    research_rates: np.ndarray,
    current_rates: np.ndarray,
    config: dict[str, Any],
    *, dt: float = DT,
) -> SlalomCalibratedV3Result:
    source = np.asarray(predicted_rates, dtype=np.float32)
    before_xy, before_yaw = integrate_rates_float32(source, dt=dt)
    calibration = config["calibration"]
    calibrated, cal_meta = apply_linear_calibration(source, research_rates, current_rates, calibration, dt=dt)
    cal_xy, cal_yaw = integrate_rates_float32(calibrated, dt=dt)
    turn = config["turn_detection"]
    events = detect_turn_events_sign_aware(
        calibrated[:, 1], threshold_degps=float(turn["threshold_degps"]),
        merge_gap_frames=int(turn["merge_gap_frames"]), min_event_frames=int(turn["min_event_frames"]),
    )
    full = config["complete_course"]
    pattern = major_turn_pattern(
        calibrated[:, 1], events, min_abs_turn_deg=float(full["major_turn_min_abs_deg"]), dt=dt,
    )
    expected_pattern = tuple(int(x) for x in full["expected_major_sign_pattern"])
    complete = pattern == expected_pattern
    protocol = config["protocol"]
    heading = calibrated
    removed_deg = 0.0
    heading_applied = False
    if bool(protocol.get("start_end_heading_same", True)) and events:
        heading, removed_deg = _close_heading_equal(
            calibrated, events, float(protocol.get("expected_net_heading_rad", 0.0)), dt=dt,
        )
        heading_applied = True
    heading_xy, heading_yaw = integrate_rates_float32(heading, dt=dt)

    final = heading
    pos_applied = False
    rms = max_abs = rms_fraction = max_fraction = 0.0
    pos = config["position_closure"]
    moving = np.abs(heading[:, 0]) > float(pos["active_speed_threshold_mps"])
    median_speed = float(np.median(np.abs(heading[moving, 0]))) if np.any(moving) else 0.0
    if complete and bool(protocol.get("start_end_position_same_for_complete_course", True)):
        candidate, rms, max_abs = _close_position(
            heading,
            active_speed_threshold_mps=float(pos["active_speed_threshold_mps"]),
            max_abs_speed_correction_mps=float(pos["probe_max_abs_speed_correction_mps"]),
            dt=dt,
        )
        rms_fraction = rms / median_speed if median_speed > 1e-12 else float("inf")
        max_fraction = max_abs / median_speed if median_speed > 1e-12 else float("inf")
        accept = bool(
            rms > 0
            and rms <= float(pos["max_rms_speed_correction_mps"])
            and max_abs <= float(pos["max_abs_speed_correction_mps"])
            and rms_fraction <= float(pos["max_rms_fraction_median_speed"])
            and max_fraction <= float(pos["max_abs_fraction_median_speed"])
        )
        if accept:
            final = candidate
            pos_applied = True
    final_xy, final_yaw = integrate_rates_float32(final, dt=dt)
    prefix = "calibrated" if bool(cal_meta.get("calibration_applied")) else "raw_v1_fallback"
    if not events:
        reason = f"{prefix}_no_turn_events"
    elif complete and pos_applied:
        reason = f"{prefix}_full_course"
    elif complete:
        reason = f"{prefix}_heading_position_guard_rejected"
    else:
        reason = f"{prefix}_partial_course_no_position_closure"
    return SlalomCalibratedV3Result(
        rates=final, applied=True, complete_course=complete, reason=reason,
        turn_count=len(events), major_turn_count=len(pattern), major_sign_pattern=pattern,
        heading_closure=heading_applied, position_closure=pos_applied,
        raw_net_heading_deg=float(np.degrees(before_yaw[-1])),
        calibrated_net_heading_deg=float(np.degrees(cal_yaw[-1])),
        final_net_heading_deg=float(np.degrees(final_yaw[-1])),
        heading_removed_deg=removed_deg,
        closure_speed_correction_rms_mps=float(rms), closure_speed_correction_max_abs_mps=float(max_abs),
        closure_speed_correction_rms_fraction_median=float(rms_fraction),
        closure_speed_correction_max_fraction_median=float(max_fraction), median_moving_speed_mps=median_speed,
        endpoint_before_m=float(np.linalg.norm(before_xy[-1])), endpoint_after_calibration_m=float(np.linalg.norm(cal_xy[-1])),
        endpoint_after_heading_m=float(np.linalg.norm(heading_xy[-1])), endpoint_after_m=float(np.linalg.norm(final_xy[-1])),
        **cal_meta,
    )
