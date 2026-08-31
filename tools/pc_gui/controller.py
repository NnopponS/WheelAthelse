from __future__ import annotations

import math
import time
import uuid
from pathlib import Path
from typing import Any

from PySide6.QtCore import QObject, QTimer, Signal

from .experiments import ExperimentStore, ExperimentTemplate
from .ipc_client import DaemonClient
from .process_manager import DaemonProcessManager
from .state import AppViewState, BoardView, PreviewBuffer, PreviewSample


class BaseController(QObject):
    state_changed = Signal(object)
    preview_changed = Signal(str)
    scan_results_changed = Signal(object)
    sessions_changed = Signal(object)
    experiments_changed = Signal(object)
    command_error = Signal(str, str)
    message = Signal(str)
    recording_finished = Signal(object)
    daemon_log = Signal(str)

    def __init__(self, parent: QObject | None = None) -> None:
        super().__init__(parent)
        self.state = AppViewState()
        self.scan_results: list[dict[str, Any]] = []
        self.sessions: list[dict[str, Any]] = []
        self.experiment_store = ExperimentStore.default()
        self.experiments: list[ExperimentTemplate] = []
        self._preview = {"L": PreviewBuffer(), "R": PreviewBuffer()}

    def preview_buffer(self, side: str) -> PreviewBuffer:
        return self._preview[side]

    def load_experiments(self) -> None:
        try:
            self.experiments = self.experiment_store.load()
        except RuntimeError as exc:
            self.command_error.emit("experiments", str(exc))
            self.experiments = []
        self.experiments_changed.emit(list(self.experiments))

    def save_experiment(self, template: ExperimentTemplate) -> None:
        try:
            self.experiments = self.experiment_store.upsert(template)
        except RuntimeError as exc:
            self.command_error.emit("experiments", str(exc))
            return
        self.experiments_changed.emit(list(self.experiments))

    def delete_experiment(self, template_id: str) -> None:
        try:
            self.experiments = self.experiment_store.delete(template_id)
        except RuntimeError as exc:
            self.command_error.emit("experiments", str(exc))
            return
        self.experiments_changed.emit(list(self.experiments))

    # Interface used by the UI. Subclasses implement the acquisition methods.
    def start(self) -> None: ...
    def close(self) -> None: ...
    def scan(self) -> None: ...
    def connect_device(self, device_id: str) -> None: ...
    def disconnect_side(self, side: str) -> None: ...
    def configure_board(
        self, side: str, *, sample_rate_hz: int, accel_range: int, gyro_range: int
    ) -> None: ...
    def sync_all(self) -> None: ...
    def refresh_status(self) -> None: ...
    def refresh_sessions(self) -> None: ...
    def export_session(self, session_id: str, output_path: str) -> None: ...
    def export_diagnostics(self, output_path: str) -> None: ...
    def recover_session(self, file_name: str) -> None: ...
    def start_record(self, metadata: dict[str, Any]) -> None: ...
    def stop_record(self) -> None: ...


class AcquisitionController(BaseController):
    """Orchestrates UI commands without owning any BLE/raw-data work."""

    def __init__(
        self,
        *,
        repo_root: Path,
        port: int = 8765,
        parent: QObject | None = None,
    ) -> None:
        super().__init__(parent)
        self.client = DaemonClient(port=port, parent=self)
        self.process_manager = DaemonProcessManager(repo_root=repo_root, port=port, parent=self)
        self.process_manager.log_line.connect(self.daemon_log)
        self.client.ready_changed.connect(self._on_ready)
        self.client.connection_changed.connect(self._on_connection)
        self.client.event_received.connect(self._on_event)
        self.client.command_failed.connect(self.command_error)
        self.client.protocol_error.connect(lambda text: self.command_error.emit("protocol", text))
        self._poll = QTimer(self)
        self._poll.setInterval(1000)
        self._poll.timeout.connect(self.refresh_status)
        self._started = False

    def start(self) -> None:
        if self._started:
            return
        self._started = True
        self.load_experiments()
        started = self.process_manager.ensure_running()
        QTimer.singleShot(650 if started else 50, self.client.connect_to_daemon)
        self._poll.start()

    def close(self) -> None:
        self._poll.stop()
        self.client.close()
        self.process_manager.stop_if_owned(recording_active=self.state.recording)

    def scan(self) -> None:
        self._command("scan", {"timeout_s": 4.0}, self._on_scan)

    def connect_device(self, device_id: str) -> None:
        self._command(
            "connect",
            {"device_id": device_id},
            lambda result: (self.message.emit(f"Connected Wheel {result.get('side', '?')}"), self.refresh_status()),
        )

    def disconnect_side(self, side: str) -> None:
        self._command(
            "disconnect",
            {"side": side},
            lambda _result: self.refresh_status(),
        )

    def configure_board(
        self, side: str, *, sample_rate_hz: int, accel_range: int, gyro_range: int
    ) -> None:
        if self.state.recording:
            self.command_error.emit("configure", "Board settings are locked while recording")
            return
        self._command(
            "configure",
            {
                "side": side,
                "sample_rate_hz": sample_rate_hz,
                "accel_range": accel_range,
                "gyro_range": gyro_range,
            },
            lambda _result: (
                self.message.emit(f"Wheel {side} settings applied"),
                self.refresh_status(),
            ),
        )

    def sync_all(self) -> None:
        sides = self.state.connected_sides()
        if not sides:
            self.command_error.emit("sync", "Connect at least one wheel first")
            return
        remaining = set(sides)
        errors: list[str] = []

        def done(side: str) -> None:
            remaining.discard(side)
            if not remaining:
                if errors:
                    self.command_error.emit("sync", "; ".join(errors))
                else:
                    self.message.emit("Clock synchronization updated")
                self.refresh_status()

        for side in sides:
            try:
                self.client.send_command(
                    "sync",
                    {"side": side, "count": 12},
                    on_success=lambda _result, side=side: done(side),
                    on_error=lambda message, side=side: (errors.append(f"{side}: {message}"), done(side)),
                )
            except RuntimeError as exc:
                errors.append(f"{side}: {exc}")
                done(side)

    def refresh_status(self) -> None:
        if not self.client.ready:
            return
        self._command("status", {}, self._apply_status, quiet=True)

    def refresh_sessions(self) -> None:
        self._command("list_sessions", {}, self._on_sessions, quiet=True)

    def export_session(self, session_id: str, output_path: str) -> None:
        self._command(
            "export_session",
            {"session_id": session_id, "output_path": output_path},
            lambda result: self.message.emit(f"CSV exported: {result.get('output_path', output_path)}"),
        )

    def export_diagnostics(self, output_path: str) -> None:
        self._command(
            "diagnostic_report",
            {"output_path": output_path},
            lambda result: self.message.emit(f"Diagnostics exported: {result.get('output_path', output_path)}"),
        )

    def recover_session(self, file_name: str) -> None:
        self._command(
            "recover",
            {"file_name": file_name},
            lambda result: (
                self.message.emit(f"Recovered: {result.get('recovered', '')}"),
                self.refresh_status(),
                self.refresh_sessions(),
            ),
        )

    def start_record(self, metadata: dict[str, Any]) -> None:
        if self.state.recording:
            self.command_error.emit("record", "A recording is already active")
            return
        sides = self.state.connected_sides()
        if not sides:
            self.command_error.emit("record", "Connect at least one wheel first")
            return
        rate = int(metadata.get("sample_rate_hz", 100))
        if rate not in {50, 100, 200}:
            self.command_error.emit("record", "Sample rate must be 50, 100, or 200 Hz")
            return

        # Configuration acknowledgements are required before START. This keeps
        # QC's configured-rate metadata aligned with the firmware state.
        pending = list(sides)

        def configure_next() -> None:
            if not pending:
                payload = dict(metadata)
                payload["sides"] = list(sides)
                payload.setdefault("sync_count", 12)
                payload.setdefault("lead_time_s", 3.0)
                payload.setdefault("ack_timeout_s", 1.0)
                self._command("start_record", payload, self._record_started)
                return
            side = pending.pop(0)
            self._command(
                "configure",
                {"side": side, "sample_rate_hz": rate},
                lambda _result: configure_next(),
            )

        for buffer in self._preview.values():
            buffer.clear()
        configure_next()

    def stop_record(self) -> None:
        if not self.state.recording:
            self.command_error.emit("record", "No recording is active")
            return
        self._command("end_record", {}, self._record_stopped)

    def _command(
        self,
        command: str,
        payload: dict[str, Any],
        callback: Any | None = None,
        *,
        quiet: bool = False,
    ) -> None:
        if not self.client.ready:
            if not quiet:
                self.command_error.emit(command, "Acquisition daemon is not ready")
            return
        try:
            self.client.send_command(
                command,
                payload,
                on_success=callback,
                on_error=None if not quiet else lambda _message: None,
            )
        except (RuntimeError, ValueError) as exc:
            if not quiet:
                self.command_error.emit(command, str(exc))

    def _on_ready(self, ready: bool) -> None:
        self.state.daemon_connected = ready
        self.state.daemon_name = "WheelAthlete Acquisition" if ready else "Offline"
        self.state_changed.emit(self.state)
        if ready:
            self.refresh_status()
            self.refresh_sessions()

    def _on_connection(self, connected: bool, text: str) -> None:
        self.state.daemon_connected = connected and self.client.ready
        self.state.daemon_name = text
        self.state_changed.emit(self.state)

    def _on_scan(self, result: dict[str, Any]) -> None:
        devices = result.get("devices", [])
        self.scan_results = [dict(item) for item in devices if isinstance(item, dict)]
        self.scan_results_changed.emit(list(self.scan_results))

    def _on_sessions(self, result: dict[str, Any]) -> None:
        sessions = result.get("sessions", [])
        self.sessions = [dict(item) for item in sessions if isinstance(item, dict)]
        self.sessions_changed.emit(list(self.sessions))

    def _apply_status(self, result: dict[str, Any]) -> None:
        self.state.daemon_connected = True
        self.state.apply_status(result)
        self.state_changed.emit(self.state)

    def _record_started(self, result: dict[str, Any]) -> None:
        self.state.recording = True
        self.state.session_id = str(result.get("session_id")) if result.get("session_id") else None
        self.state_changed.emit(self.state)
        self.message.emit("Recording started with synchronized device clocks")
        self.refresh_status()

    def _record_stopped(self, result: dict[str, Any]) -> None:
        self.state.recording = False
        self.state.session_id = None
        self.state_changed.emit(self.state)
        self.recording_finished.emit(result)
        self.refresh_status()
        self.refresh_sessions()

    def _on_event(self, event_type: str, payload: dict[str, Any]) -> None:
        if event_type == "sample_preview":
            try:
                sample = PreviewSample.from_payload(payload)
            except (KeyError, TypeError, ValueError):
                return
            self._preview[sample.side].append(sample)
            self.preview_changed.emit(sample.side)
            return
        if event_type == "recording_state":
            state = str(payload.get("state", ""))
            if state in {"started", "recording"}:
                self.state.recording = True
            elif state in {"stopped", "finalized"}:
                self.state.recording = False
            self.state_changed.emit(self.state)
        elif event_type in {"connection_state", "sync_status"}:
            self.refresh_status()
        elif event_type == "error":
            self.command_error.emit(str(payload.get("code", "acquisition")), str(payload.get("message", payload)))


class DemoController(BaseController):
    """UI-only demo source. Never writes a research session or claims BLE data."""

    def __init__(self, parent: QObject | None = None) -> None:
        super().__init__(parent)
        self.state.daemon_connected = True
        self.state.daemon_name = "DEMO — synthetic preview only"
        self.state.journal_root = str(Path.home() / "Documents" / "WheelAthlete" / "PC Sessions")
        for side, rssi in (("L", -46), ("R", -49)):
            self.state.boards[side] = BoardView(
                side=side,
                connected=True,
                device_id=f"DEMO-{side}",
                name=f"WheelAthlete-{side}",
                firmware="1.7.0",
                battery_percent=92 if side == "L" else 88,
                rssi=rssi,
                mtu=247,
                configured_rate_hz=100,
                accel_range=1,
                gyro_range=3,
                samples_hz=100.0,
                notifications_hz=10.0,
                best_rtt_ms=1.8 if side == "L" else 2.1,
                median_rtt_ms=2.4,
                drift_ppm=3.2 if side == "L" else -2.6,
                accel_scale=4 / 32768,
                gyro_scale=2000 / 32768,
            )
        self._timer = QTimer(self)
        self._timer.setInterval(100)
        self._timer.timeout.connect(self._tick)
        self._seq = 0
        self._started_ns = time.monotonic_ns()

    def start(self) -> None:
        self.load_experiments()
        self._timer.start()
        self.state_changed.emit(self.state)
        self.scan_results = [
            {"device_id": "DEMO-L", "name": "WheelAthlete-L", "rssi": -46},
            {"device_id": "DEMO-R", "name": "WheelAthlete-R", "rssi": -49},
        ]
        self.scan_results_changed.emit(list(self.scan_results))

    def close(self) -> None:
        self._timer.stop()

    def scan(self) -> None:
        self.scan_results_changed.emit(list(self.scan_results))

    def connect_device(self, device_id: str) -> None:
        self.message.emit(f"Demo device already connected: {device_id}")

    def disconnect_side(self, side: str) -> None:
        self.message.emit("Demo mode keeps both synthetic wheels connected")

    def configure_board(
        self, side: str, *, sample_rate_hz: int, accel_range: int, gyro_range: int
    ) -> None:
        board = self.state.boards[side]
        board.configured_rate_hz = sample_rate_hz
        board.accel_range = accel_range
        board.gyro_range = gyro_range
        board.accel_scale = (2, 4, 8, 16)[accel_range] / 32768
        board.gyro_scale = (250, 500, 1000, 2000)[gyro_range] / 32768
        board.samples_hz = float(sample_rate_hz)
        self.state_changed.emit(self.state)
        self.message.emit(f"Demo Wheel {side} settings applied")

    def sync_all(self) -> None:
        self.message.emit("Demo sync model refreshed")

    def refresh_status(self) -> None:
        self.state_changed.emit(self.state)

    def refresh_sessions(self) -> None:
        self.sessions_changed.emit(list(self.sessions))

    def export_session(self, session_id: str, output_path: str) -> None:
        self.message.emit("Demo mode does not export synthetic sessions")

    def export_diagnostics(self, output_path: str) -> None:
        self.message.emit("Demo mode does not write diagnostic evidence")

    def recover_session(self, file_name: str) -> None:
        self.message.emit("Demo mode has no incomplete journal")

    def start_record(self, metadata: dict[str, Any]) -> None:
        self.state.recording = True
        self.state.session_id = f"DEMO-{uuid.uuid4().hex[:8]}"
        self.state_changed.emit(self.state)
        self.message.emit("DEMO recording started — no research data is being written")

    def stop_record(self) -> None:
        self.state.recording = False
        self.state.session_id = None
        self.state_changed.emit(self.state)
        self.recording_finished.emit(
            {
                "quality": "GOOD",
                "duration_s": max(0.1, (time.monotonic_ns() - self._started_ns) / 1e9),
                "reasons": [],
                "demo": True,
            }
        )

    def _tick(self) -> None:
        t = (time.monotonic_ns() - self._started_ns) / 1e9
        for index, side in enumerate(("L", "R")):
            phase = t + index * 0.45
            accel_scale = self.state.boards[side].accel_scale
            gyro_scale = self.state.boards[side].gyro_scale
            sample = PreviewSample(
                side=side,
                seq=self._seq,
                device_us=int(t * 1_000_000) & 0xFFFFFFFF,
                pc_ns=time.monotonic_ns(),
                ax=int((0.35 * math.sin(phase * 2.3)) / accel_scale),
                ay=int((0.22 * math.sin(phase * 1.7 + 1.0)) / accel_scale),
                az=int((1.0 + 0.08 * math.sin(phase * 2.0)) / accel_scale),
                gx=int((65 * math.sin(phase * 2.8)) / gyro_scale),
                gy=int((45 * math.sin(phase * 2.1 + 0.7)) / gyro_scale),
                gz=int((35 * math.sin(phase * 1.4 + 1.4)) / gyro_scale),
            )
            self._preview[side].append(sample)
            board = self.state.boards[side]
            board.samples += 10
            board.notifications += 1
            board.samples_hz = 100 + math.sin(phase) * 0.08
            board.notifications_hz = 10 + math.sin(phase * 0.7) * 0.02
            self.preview_changed.emit(side)
        self._seq += 10
        if self._seq % 50 == 0:
            self.state_changed.emit(self.state)
