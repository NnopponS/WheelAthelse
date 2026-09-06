from __future__ import annotations

import math
import statistics
from dataclasses import dataclass


UINT32_MASK = 0xFFFFFFFF
UINT32_HALF = 0x80000000
NOMINAL_NS_PER_DEVICE_US = 1000.0


class Uint32Unwrapper:
    """Map a wrapping device ``micros()`` counter onto an integer timeline."""

    def __init__(self) -> None:
        self._last_raw: int | None = None
        self._last_unwrapped: int | None = None

    def unwrap(self, raw: int) -> int:
        raw &= UINT32_MASK
        if self._last_raw is None:
            self._last_raw = raw
            self._last_unwrapped = raw
            return raw
        assert self._last_unwrapped is not None
        forward = (raw - self._last_raw) & UINT32_MASK
        if forward < UINT32_HALF:
            value = self._last_unwrapped + forward
        else:
            # Late event from behind the current cursor.  Preserve its relative
            # position without moving the stored unwrap anchor backwards.
            backward = (self._last_raw - raw) & UINT32_MASK
            return self._last_unwrapped - backward
        self._last_raw = raw
        self._last_unwrapped = value
        return value


@dataclass(frozen=True, slots=True)
class ClockObservation:
    device_us: int
    pc_midpoint_ns: int
    rtt_ns: int


@dataclass(frozen=True, slots=True)
class ClockModel:
    slope_ns_per_us: float
    intercept_ns: float
    best_rtt_ns: int
    median_rtt_ns: int
    residual_rms_ns: float
    observation_count: int

    @property
    def drift_ppm(self) -> float:
        return (
            self.slope_ns_per_us / NOMINAL_NS_PER_DEVICE_US - 1.0
        ) * 1_000_000.0

    def device_to_pc_ns(self, device_us: int) -> int:
        return round(self.slope_ns_per_us * device_us + self.intercept_ns)

    def pc_to_device_us(self, pc_ns: int) -> int:
        if self.slope_ns_per_us == 0:
            raise ZeroDivisionError("clock model slope is zero")
        return round((pc_ns - self.intercept_ns) / self.slope_ns_per_us)

    @classmethod
    def nominal(cls, *, device_us: int, pc_ns: int, rtt_ns: int) -> "ClockModel":
        return cls(
            slope_ns_per_us=NOMINAL_NS_PER_DEVICE_US,
            intercept_ns=pc_ns - NOMINAL_NS_PER_DEVICE_US * device_us,
            best_rtt_ns=rtt_ns,
            median_rtt_ns=rtt_ns,
            residual_rms_ns=0.0,
            observation_count=1,
        )

    @classmethod
    def fit(cls, observations: list[ClockObservation]) -> "ClockModel":
        if not observations:
            raise ValueError("at least one clock observation is required")
        best = min(observations, key=lambda item: item.rtt_ns)
        median_rtt = round(statistics.median(item.rtt_ns for item in observations))
        if len(observations) == 1:
            return cls.nominal(
                device_us=best.device_us,
                pc_ns=best.pc_midpoint_ns,
                rtt_ns=best.rtt_ns,
            )

        # Use the lowest-RTT half (minimum two points). BLE delay is mostly
        # positive scheduling noise, so low-RTT observations are the least
        # biased approximation of the symmetric path assumed by NTP-lite.
        ordered = sorted(observations, key=lambda item: item.rtt_ns)
        keep_count = max(2, (len(ordered) + 1) // 2)
        kept = ordered[:keep_count]
        xs = [float(item.device_us) for item in kept]
        ys = [float(item.pc_midpoint_ns) for item in kept]
        x_mean = statistics.fmean(xs)
        y_mean = statistics.fmean(ys)
        variance = sum((x - x_mean) ** 2 for x in xs)
        if variance <= 0:
            slope = NOMINAL_NS_PER_DEVICE_US
            intercept = best.pc_midpoint_ns - slope * best.device_us
        else:
            covariance = sum((x - x_mean) * (y - y_mean) for x, y in zip(xs, ys))
            slope = covariance / variance
            intercept = y_mean - slope * x_mean

        residuals = [y - (slope * x + intercept) for x, y in zip(xs, ys)]
        rms = math.sqrt(statistics.fmean(value * value for value in residuals))
        return cls(
            slope_ns_per_us=slope,
            intercept_ns=intercept,
            best_rtt_ns=best.rtt_ns,
            median_rtt_ns=median_rtt,
            residual_rms_ns=rms,
            observation_count=len(observations),
        )
