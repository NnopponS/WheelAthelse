"""Processed trial schema and I/O."""

from __future__ import annotations

from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any

import numpy as np


@dataclass
class TrialMeta:
    trial_id: str
    split: str
    condition: str
    maneuver: str
    R: float
    L_hub: float
    alpha: float
    L_floor: float
    g: float = 9.80665
    imu_offset_m: float = 0.04
    reflector_offset_m: float = 0.066
    L_hub_meas: float = 0.0
    L_refl_meas: float = 0.0
    imu_hz: int = 100
    gt_hz: int = 20
    sync_ratio: int = 5
    duration_s: float = 0.0
    lag_s: float = 0.0
    sync_corr: float = 0.0
    n_gt: int = 0
    n_imu: int = 0
    has_gt: bool = True
    athlete: str = ""

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "TrialMeta":
        return cls(**{k: data[k] for k in cls.__dataclass_fields__ if k in data})


@dataclass
class Trial:
    """One synced dual-wheel trial ready for training.

    IMU is stored as windows of ``sync_ratio`` samples (default 5) per GT step:
    ``imu_left_windows`` shape ``(T_gt, 5, 6)``.
    """

    meta: TrialMeta
    t_gt: np.ndarray  # (T_gt,) seconds @ 20 Hz
    xyz: np.ndarray  # (T_gt, 3) chair center, origin at start
    xyz_left: np.ndarray  # (T_gt, 3) L_WC after same transform
    xyz_right: np.ndarray  # (T_gt, 3) R_WC
    angles: np.ndarray  # (T_gt, 3) [theta, psi, phi]
    v: np.ndarray  # (T_gt,)
    omega: np.ndarray  # (T_gt,)
    theta_left: np.ndarray  # (T_gt,)
    theta_right: np.ndarray  # (T_gt,)
    imu_left_windows: np.ndarray  # (T_gt, 5, 6) SI units
    imu_right_windows: np.ndarray  # (T_gt, 5, 6)
    t_imu: np.ndarray = field(default_factory=lambda: np.array([], dtype=float))
    imu_left: np.ndarray = field(default_factory=lambda: np.zeros((0, 6)))
    imu_right: np.ndarray = field(default_factory=lambda: np.zeros((0, 6)))

    @property
    def imu_dual_windows(self) -> np.ndarray:
        """(T_gt, 5, 12) left||right per window."""
        return np.concatenate([self.imu_left_windows, self.imu_right_windows], axis=-1)

    def save(self, path: str | Path) -> None:
        path = Path(path)
        path.parent.mkdir(parents=True, exist_ok=True)
        np.savez_compressed(
            path,
            meta=np.array(self.meta.to_dict(), dtype=object),
            t_gt=self.t_gt,
            xyz=self.xyz,
            xyz_left=self.xyz_left,
            xyz_right=self.xyz_right,
            angles=self.angles,
            v=self.v,
            omega=self.omega,
            theta_left=self.theta_left,
            theta_right=self.theta_right,
            imu_left_windows=self.imu_left_windows,
            imu_right_windows=self.imu_right_windows,
            t_imu=self.t_imu,
            imu_left=self.imu_left,
            imu_right=self.imu_right,
        )

    @classmethod
    def load(cls, path: str | Path) -> "Trial":
        data = np.load(path, allow_pickle=True)
        meta = TrialMeta.from_dict(data["meta"].item())
        return cls(
            meta=meta,
            t_gt=data["t_gt"],
            xyz=data["xyz"],
            xyz_left=data["xyz_left"],
            xyz_right=data["xyz_right"],
            angles=data["angles"],
            v=data["v"],
            omega=data["omega"],
            theta_left=data["theta_left"],
            theta_right=data["theta_right"],
            imu_left_windows=data["imu_left_windows"],
            imu_right_windows=data["imu_right_windows"],
            t_imu=data["t_imu"] if "t_imu" in data else np.array([], dtype=float),
            imu_left=data["imu_left"] if "imu_left" in data else np.zeros((0, 6)),
            imu_right=data["imu_right"] if "imu_right" in data else np.zeros((0, 6)),
        )


def floor_track_width(L_hub: float, R: float = 0.0, alpha: float = 0.0) -> float:
    """Track width for IK. Camber disabled → always ``L_hub``."""
    del R, alpha
    return float(L_hub)
