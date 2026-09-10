from __future__ import annotations

from collections.abc import Iterator
from typing import Any

import numpy as np

MIN_QUIET_FRAMES = 20  # 1.0 s at the 20 Hz trajectory cadence


def quiet_mask(omega_l: Any, omega_r: Any, *, quiet_abs: float = 0.25) -> np.ndarray:
    left = np.asarray(omega_l, dtype=np.float64)
    right = np.asarray(omega_r, dtype=np.float64)
    n = min(len(left), len(right))
    return (np.abs(left[:n]) < float(quiet_abs)) & (np.abs(right[:n]) < float(quiet_abs))


def runs(mask: Any) -> Iterator[tuple[int, int, bool]]:
    values = np.asarray(mask, dtype=bool).reshape(-1)
    if values.size == 0:
        return
    start = 0
    current = bool(values[0])
    for index in range(1, int(values.size)):
        value = bool(values[index])
        if value != current:
            yield start, index, current
            start = index
            current = value
    yield start, int(values.size), current


def debounce_quiet(mask: Any, *, min_quiet_frames: int = MIN_QUIET_FRAMES) -> np.ndarray:
    """Retain sustained quiet runs only, matching the documented >=1 s pause rule."""
    values = np.asarray(mask, dtype=bool).reshape(-1)
    out = np.zeros(values.shape, dtype=bool)
    minimum = max(1, int(min_quiet_frames))
    for start, stop, is_quiet in runs(values):
        if is_quiet and stop - start >= minimum:
            out[start:stop] = True
    return out
