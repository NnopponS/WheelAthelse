"""Experimental fixed-course Slalom adapter v2 for the Windows research app."""
from __future__ import annotations

from dataclasses import dataclass
from typing import Any

import numpy as np
from .slalom_course import DT, _close_position, integrate_rates_float32


@dataclass(frozen=True)
class SlalomCourseV2Result:
    rates: np.ndarray
    metadata: dict[str, Any]


def detect_turn_events_sign_aware(yaw_rate_radps: np.ndarray, *, threshold_degps: float = 20.0, merge_gap_frames: int = 10, min_event_frames: int = 8) -> list[tuple[int, int]]:
    w = np.asarray(yaw_rate_radps, dtype=float)
    if w.ndim != 1 or not np.isfinite(w).all():
        raise ValueError("yaw rate must be finite and one-dimensional")
    active = np.abs(w) > np.deg2rad(float(threshold_degps))
    edges = np.diff(np.r_[False, active, False].astype(np.int8))
    raw = list(zip(np.flatnonzero(edges == 1).tolist(), np.flatnonzero(edges == -1).tolist()))
    merged: list[list[int]] = []
    for start, stop in raw:
        sign = 1 if float(np.mean(w[start:stop])) >= 0.0 else -1
        if merged and sign == merged[-1][2] and start - merged[-1][1] <= int(merge_gap_frames):
            merged[-1][1] = stop
        else:
            merged.append([start, stop, sign])
    return [(a, z) for a, z, _ in merged if z - a >= int(min_event_frames)]


def _major_pattern(rates: np.ndarray, events: list[tuple[int, int]], min_abs_deg: float) -> tuple[int, ...]:
    signs = []
    for a, z in events:
        delta = float(np.sum(rates[a:z, 1].astype(float)) * DT)
        if abs(np.degrees(delta)) >= float(min_abs_deg):
            signs.append(1 if delta >= 0 else -1)
    return tuple(signs)


def _apply_corrections(rates: np.ndarray, events: list[tuple[int, int]], corrections: np.ndarray) -> np.ndarray:
    out = np.asarray(rates, dtype=np.float32).copy()
    for (a, z), correction in zip(events, corrections):
        out[a:z, 1] = (out[a:z, 1].astype(np.float64) + float(correction) / ((z - a) * DT)).astype(np.float32)
    return out


def _optimize_heading(rates: np.ndarray, events: list[tuple[int, int]], config: dict[str, Any]) -> tuple[np.ndarray, np.ndarray, dict[str, Any]]:
    try:
        from scipy.optimize import least_squares
    except ImportError as exc:
        raise RuntimeError("SciPy is required for Slalom course adapter v2") from exc
    _, yaw = integrate_rates_float32(rates)
    expected = float(config["protocol"]["expected_net_heading_rad"])
    opt = config["event_optimizer"]
    total = expected - float(yaw[-1])
    equal = np.full(len(events), total / len(events), dtype=float)
    sigma = np.deg2rad(float(opt["event_correction_sigma_deg"]))
    bound = np.deg2rad(float(opt["max_event_deviation_deg"]))
    pos_scale = float(opt["position_objective_scale_m"])
    def unpack(q: np.ndarray) -> np.ndarray:
        c = equal.copy(); c[:-1] += q; c[-1] -= float(np.sum(q)); return c
    def residual(q: np.ndarray) -> np.ndarray:
        c = unpack(q); corrected = _apply_corrections(rates, events, c); xy, _ = integrate_rates_float32(corrected)
        return np.r_[xy[-1].astype(float) / pos_scale, (c - equal) / sigma]
    q0 = np.zeros(len(events) - 1, dtype=float)
    fit = least_squares(residual, q0, bounds=(np.full_like(q0, -bound), np.full_like(q0, bound)), max_nfev=int(opt["max_nfev"]))
    correction = unpack(np.asarray(fit.x, dtype=float))
    max_dev = float(np.max(np.abs(correction - equal)))
    if max_dev > bound + 1e-9:
        correction = equal
        rejected = True
    else:
        rejected = False
    corrected = _apply_corrections(rates, events, correction)
    return corrected, correction, {"cost": float(fit.cost), "nfev": int(fit.nfev), "derived_bound_rejected": rejected}


def apply_slalom_course_v2(rates: np.ndarray, config: dict[str, Any]) -> SlalomCourseV2Result:
    source = np.asarray(rates, dtype=np.float32)
    if source.ndim != 2 or source.shape[1] != 2 or len(source) < 3 or not np.isfinite(source).all():
        raise ValueError("rates must be finite (T,2)")
    before_xy, before_yaw = integrate_rates_float32(source)
    td, full = config["turn_detection"], config["complete_course"]
    events = detect_turn_events_sign_aware(source[:, 1], threshold_degps=float(td["threshold_degps"]), merge_gap_frames=int(td["merge_gap_frames"]), min_event_frames=int(td["min_event_frames"]))
    pattern = _major_pattern(source, events, float(full["major_turn_min_abs_deg"]))
    expected_pattern = tuple(int(v) for v in full["expected_major_sign_pattern"])
    if pattern != expected_pattern:
        return SlalomCourseV2Result(source.copy(), {"adapter_version": 2, "applied": False, "heading_closure": False, "position_closure": False, "complete_course": False, "reason": "major_turn_pattern_mismatch", "turn_count": len(events), "major_turn_count": len(pattern), "major_sign_pattern": list(pattern), "expected_major_sign_pattern": list(expected_pattern), "endpoint_before_m": float(np.linalg.norm(before_xy[-1])), "endpoint_after_m": float(np.linalg.norm(before_xy[-1])), "raw_net_heading_deg": float(np.degrees(before_yaw[-1])), "uses_c3d_at_inference": False})
    heading_rates, corrections, optimizer = _optimize_heading(source, events, config)
    yaw_xy, yaw = integrate_rates_float32(heading_rates)
    pc = config["position_closure"]
    moving = np.abs(heading_rates[:, 0]) > float(pc["active_speed_threshold_mps"])
    median_speed = float(np.median(np.abs(heading_rates[moving, 0]))) if np.any(moving) else 0.0
    candidate, rms, max_abs = _close_position(heading_rates, active_speed_threshold_mps=float(pc["active_speed_threshold_mps"]), max_abs_speed_correction_mps=float(pc["probe_max_abs_speed_correction_mps"]), dt=DT)
    rms_frac = rms / median_speed if median_speed > 1e-12 else float("inf")
    max_frac = max_abs / median_speed if median_speed > 1e-12 else float("inf")
    accept = bool(rms > 0 and rms <= float(pc["max_rms_speed_correction_mps"]) and max_abs <= float(pc["max_abs_speed_correction_mps"]) and rms_frac <= float(pc["max_rms_fraction_median_speed"]) and max_frac <= float(pc["max_abs_fraction_median_speed"]))
    final = candidate if accept else heading_rates
    final_xy, final_yaw = integrate_rates_float32(final)
    equal_deg = float(np.degrees((float(config["protocol"]["expected_net_heading_rad"]) - float(before_yaw[-1])) / len(events)))
    corrections_deg = [float(v) for v in np.degrees(corrections)]
    meta = {"adapter_version": 2, "applied": True, "heading_closure": True, "complete_course": True, "reason": "applied_full_course" if accept else "yaw_applied_position_guard_rejected", "turn_count": len(events), "major_turn_count": len(pattern), "major_sign_pattern": list(pattern), "expected_major_sign_pattern": list(expected_pattern), "raw_net_heading_deg": float(np.degrees(before_yaw[-1])), "optimized_net_heading_deg": float(np.degrees(yaw[-1])), "final_net_heading_deg": float(np.degrees(final_yaw[-1])), "event_corrections_deg": corrections_deg, "max_event_deviation_from_equal_deg": max((abs(v - equal_deg) for v in corrections_deg), default=0.0), "optimizer_cost": optimizer["cost"], "optimizer_nfev": optimizer["nfev"], "position_closure": accept, "speed_correction_rms_mps": float(rms), "speed_correction_max_abs_mps": float(max_abs), "speed_correction_rms_fraction_median": float(rms_frac), "speed_correction_max_fraction_median": float(max_frac), "median_moving_speed_mps": median_speed, "endpoint_before_m": float(np.linalg.norm(before_xy[-1])), "endpoint_after_yaw_m": float(np.linalg.norm(yaw_xy[-1])), "endpoint_after_m": float(np.linalg.norm(final_xy[-1])), "uses_c3d_at_inference": False}
    return SlalomCourseV2Result(final, meta)
