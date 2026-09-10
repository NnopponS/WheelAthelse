"""Protocol-aware Slalom constraints for explicit offline research models.

This module consumes only predicted signed speed/yaw-rate plus a declared course
configuration. It never reads C3D ground truth. Non-Slalom sessions must remain
an exact no-op at the caller.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

import numpy as np

DT = 0.05


@dataclass(frozen=True, slots=True)
class SlalomCourseResult:
    rates: np.ndarray
    heading_closure: bool
    position_closure: bool
    turn_count: int
    removed_net_heading_deg: float
    speed_correction_rms_mps: float
    speed_correction_max_abs_mps: float
    endpoint_before_m: float
    endpoint_after_m: float


def integrate_rates_float32(
    rates: np.ndarray, dt: float = DT
) -> tuple[np.ndarray, np.ndarray]:
    """Match the research midpoint integrator using float32 throughout."""
    r = np.asarray(rates, dtype=np.float32)
    if r.ndim != 2 or r.shape[1] != 2 or not np.isfinite(r).all():
        raise ValueError("rates must be finite (T,2) [signed speed, yaw rate]")
    n = len(r)
    xy = np.zeros((n, 2), dtype=np.float32)
    yaw = np.zeros(n, dtype=np.float32)
    if n <= 1:
        return xy, yaw
    dpsi = (np.float32(0.5) * (r[1:, 1] + r[:-1, 1]) * np.float32(dt)).astype(
        np.float32
    )
    yaw[1:] = np.cumsum(dpsi, dtype=np.float32)
    vmid = (np.float32(0.5) * (r[1:, 0] + r[:-1, 0])).astype(np.float32)
    heading_mid = (yaw[:-1] + np.float32(0.5) * dpsi).astype(np.float32)
    dx = (vmid * np.cos(heading_mid).astype(np.float32) * np.float32(dt)).astype(
        np.float32
    )
    dy = (vmid * np.sin(heading_mid).astype(np.float32) * np.float32(dt)).astype(
        np.float32
    )
    xy[1:, 0] = np.cumsum(dx, dtype=np.float32)
    xy[1:, 1] = np.cumsum(dy, dtype=np.float32)
    return xy, yaw


def detect_turn_events(
    yaw_rate_radps: np.ndarray,
    *,
    threshold_degps: float,
    merge_gap_frames: int,
    min_event_frames: int,
) -> list[tuple[int, int]]:
    w = np.asarray(yaw_rate_radps, dtype=np.float32)
    if w.ndim != 1 or not np.isfinite(w).all():
        raise ValueError("yaw rate must be a finite one-dimensional array")
    active = np.abs(w) > np.deg2rad(np.float32(threshold_degps))
    edges = np.diff(np.r_[False, active, False].astype(np.int8))
    raw = list(
        zip(np.flatnonzero(edges == 1).tolist(), np.flatnonzero(edges == -1).tolist())
    )
    merged: list[list[int]] = []
    for start, stop in raw:
        if merged and start - merged[-1][1] <= int(merge_gap_frames):
            merged[-1][1] = stop
        else:
            merged.append([start, stop])
    return [
        (start, stop) for start, stop in merged if stop - start >= int(min_event_frames)
    ]


def _midpoint_integral(values: np.ndarray, dt: float) -> float:
    v = np.asarray(values, dtype=np.float64)
    if len(v) < 2:
        return 0.0
    return float(np.sum(0.5 * (v[1:] + v[:-1])) * float(dt))


def _close_heading(
    rates: np.ndarray,
    events: list[tuple[int, int]],
    *,
    expected_net_heading_rad: float,
    dt: float,
) -> tuple[np.ndarray, float]:
    out = np.asarray(rates, dtype=np.float32).copy()
    if not events:
        return out, 0.0
    error = _midpoint_integral(out[:, 1], dt) - float(expected_net_heading_rad)
    weights = np.zeros(len(out), dtype=np.float64)
    for start, stop in events:
        if not (0 <= start < stop <= len(out)):
            raise ValueError("turn event outside rate sequence")
        weights[start:stop] = 1.0 / float(stop - start)
    integral = _midpoint_integral(weights, dt)
    if integral <= 1e-12:
        return out, 0.0
    out[:, 1] = (out[:, 1].astype(np.float64) - error * weights / integral).astype(
        np.float32
    )
    return out, float(np.degrees(error))


def _close_position(
    rates: np.ndarray,
    *,
    active_speed_threshold_mps: float,
    max_abs_speed_correction_mps: float,
    dt: float,
) -> tuple[np.ndarray, float, float]:
    out = np.asarray(rates, dtype=np.float32).copy()
    if len(out) < 3:
        return out, 0.0, 0.0
    xy, yaw = integrate_rates_float32(out, dt=dt)
    speed = out[:, 0].astype(np.float64)
    dpsi = (
        0.5
        * (out[1:, 1].astype(np.float64) + out[:-1, 1].astype(np.float64))
        * float(dt)
    )
    heading_mid = yaw[:-1].astype(np.float64) + 0.5 * dpsi
    directions = np.stack([np.cos(heading_mid), np.sin(heading_mid)], axis=0)
    matrix = np.zeros((2, len(speed)), dtype=np.float64)
    contribution = 0.5 * float(dt) * directions
    matrix[:, :-1] += contribution
    matrix[:, 1:] += contribution
    active = np.flatnonzero(np.abs(speed) > float(active_speed_threshold_mps))
    if len(active) < 3:
        return out, 0.0, 0.0
    basis = matrix[:, active]
    gram = basis @ basis.T
    if float(np.linalg.det(gram)) <= 1e-12:
        return out, 0.0, 0.0
    delta = basis.T @ np.linalg.solve(gram, -np.asarray(xy[-1], dtype=np.float64))
    max_abs = float(np.max(np.abs(delta))) if len(delta) else 0.0
    if max_abs > float(max_abs_speed_correction_mps):
        return out, 0.0, max_abs
    out[active, 0] = (speed[active] + delta).astype(np.float32)
    return out, float(np.sqrt(np.mean(delta**2))), max_abs


def apply_slalom_course_constraints(
    rates: np.ndarray, config: dict[str, Any]
) -> SlalomCourseResult:
    """Apply a validated config that contains no optical/reference values."""
    source = np.asarray(rates, dtype=np.float32)
    before_xy, _ = integrate_rates_float32(source)
    protocol = config.get("protocol") or {}
    turn = config.get("turn_detection") or {}
    position = config.get("position_closure") or {}
    events = detect_turn_events(
        source[:, 1],
        threshold_degps=float(turn["threshold_degps"]),
        merge_gap_frames=int(turn["merge_gap_frames"]),
        min_event_frames=int(turn["min_event_frames"]),
    )
    heading_rates, removed_deg = _close_heading(
        source,
        events,
        expected_net_heading_rad=float(protocol.get("expected_net_heading_rad", 0.0)),
        dt=DT,
    )
    constrained = heading_rates
    rms = 0.0
    max_abs = 0.0
    position_applied = False
    if bool(protocol.get("start_end_position_same_for_complete_course", False)) and len(
        events
    ) >= int(position["min_turn_events"]):
        candidate, rms, max_abs = _close_position(
            heading_rates,
            active_speed_threshold_mps=float(position["active_speed_threshold_mps"]),
            max_abs_speed_correction_mps=float(
                position["max_abs_speed_correction_mps"]
            ),
            dt=DT,
        )
        if rms > 0.0:
            constrained = candidate
            position_applied = True
    after_xy, _ = integrate_rates_float32(constrained)
    return SlalomCourseResult(
        rates=constrained,
        heading_closure=bool(events and protocol.get("start_end_heading_same", False)),
        position_closure=position_applied,
        turn_count=len(events),
        removed_net_heading_deg=removed_deg,
        speed_correction_rms_mps=rms,
        speed_correction_max_abs_mps=max_abs,
        endpoint_before_m=float(np.linalg.norm(before_xy[-1]))
        if len(before_xy)
        else 0.0,
        endpoint_after_m=float(np.linalg.norm(after_xy[-1])) if len(after_xy) else 0.0,
    )
