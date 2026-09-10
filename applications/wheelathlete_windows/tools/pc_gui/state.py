from __future__ import annotations

from collections import deque
from dataclasses import dataclass, field
from typing import Any


PREVIEW_POINTS = 300  # 30 s at the daemon's ~10 Hz preview cadence.


def _as_float(value: Any) -> float | None:
    if isinstance(value, (int, float)):
        return float(value)
    return None


def _as_int(value: Any) -> int | None:
    if isinstance(value, bool):
        return int(value)
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        return int(value)
    return None


@dataclass(slots=True)
class PreviewSample:
    side: str
    seq: int
    device_us: int
    pc_ns: int
    ax: int
    ay: int
    az: int
    gx: int
    gy: int
    gz: int

    @classmethod
    def from_payload(cls, payload: dict[str, Any]) -> "PreviewSample":
        side = str(payload.get("side", ""))
        if side not in {"L", "R", "C"}:
            raise ValueError(f"invalid preview side: {side!r}")
        return cls(
            side=side,
            seq=int(payload["seq"]),
            device_us=int(payload["timestamp_device_us"]),
            pc_ns=int(payload["timestamp_pc_monotonic_ns"]),
            ax=int(payload["ax_raw"]),
            ay=int(payload["ay_raw"]),
            az=int(payload["az_raw"]),
            gx=int(payload["gx_raw"]),
            gy=int(payload["gy_raw"]),
            gz=int(payload["gz_raw"]),
        )


@dataclass(slots=True)
class PreviewBuffer:
    maxlen: int = PREVIEW_POINTS
    _samples: deque[PreviewSample] = field(init=False)

    def __post_init__(self) -> None:
        if self.maxlen < 2:
            raise ValueError("maxlen must be >= 2")
        self._samples = deque(maxlen=self.maxlen)

    def append(self, sample: PreviewSample) -> None:
        self._samples.append(sample)

    def clear(self) -> None:
        self._samples.clear()

    def values(self) -> tuple[PreviewSample, ...]:
        return tuple(self._samples)

    def latest(self) -> PreviewSample | None:
        return self._samples[-1] if self._samples else None


@dataclass(slots=True)
class BoardView:
    side: str
    connected: bool = False
    device_id: str | None = None
    name: str = "Not connected"
    firmware: str = "—"
    battery_percent: int | None = None
    rssi: int | None = None
    mtu: int | None = None
    configured_rate_hz: int | None = None
    accel_range: int | None = None
    gyro_range: int | None = None
    samples_hz: float | None = None
    notifications_hz: float | None = None
    samples: int = 0
    notifications: int = 0
    sequence_gaps: int = 0
    duplicates: int = 0
    out_of_order: int = 0
    malformed_packets: int = 0
    queue_depth: int = 0
    queue_high_water: int = 0
    queue_overflow_faults: int = 0
    produced: int | None = None
    notified: int | None = None
    acquisition_state: int | None = None
    firmware_queue_drops: int | None = None
    transport_failures: int | None = None
    firmware_queue_depth: int | None = None
    fifo_faults: int | None = None
    fifo_dropped_samples: int | None = None
    best_rtt_ms: float | None = None
    median_rtt_ms: float | None = None
    drift_ppm: float | None = None
    residual_rms_ms: float | None = None
    accel_scale: float = 1.0
    gyro_scale: float = 1.0
    fatal_fault: dict[str, Any] | None = None

    @classmethod
    def from_status(cls, side: str, value: dict[str, Any] | None) -> "BoardView":
        data = value or {}
        info = data.get("info") if isinstance(data.get("info"), dict) else {}
        health = data.get("health") if isinstance(data.get("health"), dict) else {}
        clock = data.get("clock") if isinstance(data.get("clock"), dict) else {}
        connected = bool(data.get("connected"))
        name = str(
            info.get("name")
            or info.get("advertised_name")
            or (f"Wheel {side}" if connected else "Not connected")
        )
        return cls(
            side=side,
            connected=connected,
            device_id=str(data["device_id"]) if data.get("device_id") else None,
            name=name,
            firmware=str(info.get("firmware", "—")),
            battery_percent=_as_int(info.get("battery_percent")),
            rssi=_as_int(info.get("rssi")),
            mtu=_as_int(data.get("mtu")),
            configured_rate_hz=_as_int(info.get("sample_rate_hz")),
            accel_range=_as_int(info.get("accel_range")),
            gyro_range=_as_int(info.get("gyro_range")),
            samples_hz=_as_float(data.get("samples_hz")),
            notifications_hz=_as_float(data.get("notifications_hz")),
            samples=int(data.get("samples", 0) or 0),
            notifications=int(data.get("notifications", 0) or 0),
            sequence_gaps=int(data.get("sequence_gaps", 0) or 0),
            duplicates=int(data.get("duplicates", 0) or 0),
            out_of_order=int(data.get("out_of_order", 0) or 0),
            malformed_packets=int(data.get("malformed_packets", 0) or 0),
            queue_depth=int(data.get("queue_depth", 0) or 0),
            queue_high_water=int(data.get("queue_high_water", 0) or 0),
            queue_overflow_faults=int(data.get("queue_overflow_faults", 0) or 0),
            produced=_as_int(health.get("produced")),
            notified=_as_int(health.get("notified")),
            acquisition_state=_as_int(health.get("state")),
            firmware_queue_drops=_as_int(health.get("queue_drops")),
            transport_failures=_as_int(health.get("transport_failures")),
            firmware_queue_depth=_as_int(health.get("queue_depth")),
            fifo_faults=_as_int(health.get("fifo_faults")),
            fifo_dropped_samples=_as_int(health.get("fifo_dropped_samples")),
            best_rtt_ms=(
                float(clock["best_rtt_ns"]) / 1_000_000
                if isinstance(clock.get("best_rtt_ns"), (int, float))
                else None
            ),
            median_rtt_ms=(
                float(clock["median_rtt_ns"]) / 1_000_000
                if isinstance(clock.get("median_rtt_ns"), (int, float))
                else None
            ),
            drift_ppm=_as_float(clock.get("drift_ppm")),
            residual_rms_ms=(
                float(clock["residual_rms_ns"]) / 1_000_000
                if isinstance(clock.get("residual_rms_ns"), (int, float))
                else None
            ),
            accel_scale=float(info.get("accel_scale", 1.0) or 1.0),
            gyro_scale=float(info.get("gyro_scale", 1.0) or 1.0),
            fatal_fault=data.get("fatal_fault") if isinstance(data.get("fatal_fault"), dict) else None,
        )

    @property
    def loss_count(self) -> int:
        values = [
            self.sequence_gaps,
            self.queue_overflow_faults,
            self.firmware_queue_drops or 0,
            self.fifo_dropped_samples or 0,
        ]
        return sum(values)

    @property
    def healthy(self) -> bool:
        return (
            self.connected
            and self.loss_count == 0
            and self.fatal_fault is None
            and self.acquisition_state not in {3, 4}
        )

    @property
    def fault_summary(self) -> str | None:
        if self.fatal_fault:
            return str(self.fatal_fault.get("message") or self.fatal_fault.get("code") or "Host acquisition fault")
        faults = [
            (self.sequence_gaps, "host sequence gap"),
            (self.queue_overflow_faults, "host notification queue overflow"),
            (self.firmware_queue_drops or 0, "firmware sample queue drop"),
            (self.fifo_dropped_samples or 0, "firmware FIFO sample loss"),
            (self.fifo_faults or 0, "firmware FIFO fault"),
            (self.malformed_packets, "malformed BLE packet"),
        ]
        for count, label in faults:
            if count:
                return f"{label}: {count}"
        if self.acquisition_state == 3:
            return f"BLE notification retry active; cumulative failures: {self.transport_failures or 0}"
        if self.acquisition_state == 4:
            return "Firmware reported an acquisition error"
        return None


@dataclass(slots=True)
class AppViewState:
    daemon_connected: bool = False
    daemon_name: str = "Offline"
    recording: bool = False
    recording_starting: bool = False
    countdown: int | None = None
    recording_started_utc_ms: int | None = None
    recording_target_pc_ns: int | None = None
    live: bool = False
    live_sides: tuple[str, ...] = ()
    live_busy: bool = False
    scanning: bool = False
    connecting: bool = False
    session_id: str | None = None
    journal_root: str = ""
    incomplete_sessions: tuple[str, ...] = ()
    journal: dict[str, Any] | None = None
    ipc: dict[str, Any] = field(default_factory=dict)
    boards: dict[str, BoardView] = field(
        default_factory=lambda: {
            "L": BoardView("L"), "R": BoardView("R"), "C": BoardView("C")
        }
    )

    def apply_status(self, payload: dict[str, Any]) -> None:
        boards = payload.get("boards") if isinstance(payload.get("boards"), dict) else {}
        self.boards = {
            side: BoardView.from_status(side, boards.get(side))
            for side in ("L", "R", "C")
        }
        self.recording = bool(payload.get("recording"))
        self.recording_starting = bool(payload.get("recording_starting"))
        started_utc = payload.get("recording_started_utc_ms")
        self.recording_started_utc_ms = int(started_utc) if started_utc is not None else None
        self.live = bool(payload.get("live"))
        live_sides = payload.get("live_sides", [])
        self.live_sides = tuple(
            str(side) for side in live_sides if side in {"L", "R", "C"}
        )
        self.session_id = str(payload["session_id"]) if payload.get("session_id") else None
        self.journal_root = str(payload.get("journal_root", ""))
        incomplete = payload.get("incomplete_sessions", [])
        self.incomplete_sessions = tuple(str(item) for item in incomplete if isinstance(item, str))
        self.journal = payload.get("journal") if isinstance(payload.get("journal"), dict) else None
        self.ipc = payload.get("ipc") if isinstance(payload.get("ipc"), dict) else {}

    def connected_sides(self) -> tuple[str, ...]:
        return tuple(
            side for side in ("L", "R", "C") if self.boards[side].connected
        )
