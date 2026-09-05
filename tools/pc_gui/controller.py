from __future__ import annotations

import math
import time
import uuid
from pathlib import Path
from typing import Any

from PySide6.QtCore import QObject, QTimer, Signal

import csv
import json
from .ipc_client import DaemonClient
from .process_manager import DaemonProcessManager
from .state import AppViewState, BoardView, PreviewBuffer, PreviewSample


def sanitize_name(name: Any) -> str:
    text = str(name).strip() if name is not None else ""
    cleaned = "".join("_" if ord(ch) < 32 or ch in '<>:"/\\|?*' else ch for ch in text).strip(" .")
    return cleaned or "Untitled"


def _gui_settings_path() -> Path:
    return Path.home() / "Documents" / "WheelAthlete" / "gui_settings.json"


def load_gui_settings() -> dict[str, Any]:
    path = _gui_settings_path()
    if path.exists():
        try:
            value = json.loads(path.read_text(encoding="utf-8"))
            if isinstance(value, dict):
                return value
        except (OSError, json.JSONDecodeError):
            pass
    return {}


def save_gui_settings(settings: dict[str, Any]) -> None:
    path = _gui_settings_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        path.write_text(json.dumps(settings, indent=2), encoding="utf-8")
    except OSError:
        pass


class BaseController(QObject):
    state_changed = Signal(object)
    preview_changed = Signal(str)
    scan_results_changed = Signal(object)
    sessions_changed = Signal(object)
    command_error = Signal(str, str)
    message = Signal(str)
    recording_finished = Signal(object)
    daemon_log = Signal(str)

    def __init__(self, parent: QObject | None = None) -> None:
        super().__init__(parent)
        self.state = AppViewState()
        self.scan_results: list[dict[str, Any]] = []
        self.sessions: list[dict[str, Any]] = []
        self._preview = {"L": PreviewBuffer(), "R": PreviewBuffer()}

    def preview_buffer(self, side: str) -> PreviewBuffer:
        return self._preview[side]

    # Interface used by the UI. Subclasses implement the acquisition methods.
    def start(self) -> None: ...
    def close(self) -> None: ...
    def scan(self) -> None: ...
    def connect_device(self, device_id: str) -> None: ...
    def connect_devices(self, device_ids: list[str]) -> None: ...
    def disconnect_side(self, side: str) -> None: ...
    def configure_board(
        self, side: str, *, sample_rate_hz: int, accel_range: int, gyro_range: int
    ) -> None: ...
    def sync_all(self) -> None: ...
    def start_live(self) -> None: ...
    def stop_live(self) -> None: ...
    def refresh_status(self) -> None: ...
    def refresh_sessions(self) -> None: ...
    def set_session_folder(self, folder_path: str | Path) -> None: ...
    def export_session(self, session_id: str, output_path: str) -> None: ...
    def export_sessions(
        self, sessions: list[dict[str, Any]], target_directory: str | Path
    ) -> list[str]: ...
    def load_session_data(self, session_id: str) -> dict[str, Any]: ...
    def delete_session(self, session_id: str) -> None: ...
    def delete_sessions(self, session_ids: list[str]) -> None: ...
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
        settings = load_gui_settings()
        saved_folder = settings.get("session_folder")
        if saved_folder:
            self.state.journal_root = str(saved_folder)

    def start(self) -> None:
        if self._started:
            return
        self._started = True
        started = self.process_manager.ensure_running()
        QTimer.singleShot(650 if started else 50, self.client.connect_to_daemon)
        self._poll.start()

    def close(self) -> None:
        self._poll.stop()
        self.client.close()
        self.process_manager.stop_if_owned(
            recording_active=self.state.recording or self.state.recording_starting
        )

    def scan(self) -> None:
        if (
            self.state.scanning
            or self.state.connecting
            or self.state.recording
            or self.state.recording_starting
        ):
            return
        self.state.scanning = True
        self.state_changed.emit(self.state)
        self.message.emit("Scanning for WheelAthlete devices…")
        self._command(
            "scan",
            {"timeout_s": 8.0, "attempts": 2},
            self._on_scan,
            on_error=lambda _message: self._finish_scan(),
        )

    def connect_device(self, device_id: str) -> None:
        self.connect_devices([device_id])

    def connect_devices(self, device_ids: list[str]) -> None:
        if (
            self.state.connecting
            or self.state.scanning
            or self.state.recording
            or self.state.recording_starting
            or self.state.live
        ):
            return
        connected_ids = {
            board.device_id for board in self.state.boards.values() if board.device_id
        }
        pending = list(dict.fromkeys(device_id for device_id in device_ids if device_id and device_id not in connected_ids))
        if not pending:
            self.message.emit("All discovered wheels are already connected")
            return

        self.state.connecting = True
        self.state_changed.emit(self.state)
        total = len(pending)
        connected = 0

        def finish() -> None:
            self.state.connecting = False
            self.state_changed.emit(self.state)
            self.message.emit(f"Connected {connected} of {total} wheel(s)")
            self.refresh_status()

        def connect_next() -> None:
            nonlocal connected
            if not pending:
                finish()
                return
            device_id = pending.pop(0)
            self.message.emit(f"Connecting wheel {connected + 1} of {total}…")

            def succeeded(result: dict[str, Any]) -> None:
                nonlocal connected
                connected += 1
                self.message.emit(f"Connected Wheel {result.get('side', '?')}")
                connect_next()

            self._command(
                "connect",
                {"device_id": device_id},
                succeeded,
                on_error=lambda _message: connect_next(),
            )

        connect_next()

    def disconnect_side(self, side: str) -> None:
        self._command(
            "disconnect",
            {"side": side},
            lambda _result: self.refresh_status(),
        )

    def configure_board(
        self, side: str, *, sample_rate_hz: int, accel_range: int, gyro_range: int
    ) -> None:
        if self.state.recording or self.state.recording_starting or self.state.live:
            self.command_error.emit(
                "configure", "Stop live preview or recording before changing board settings"
            )
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

    def start_live(self) -> None:
        sides = self.state.connected_sides()
        if not sides:
            self.command_error.emit("live", "Connect at least one wheel first")
            return
        if (
            self.state.live
            or self.state.live_busy
            or self.state.recording
            or self.state.recording_starting
        ):
            return
        for buffer in self._preview.values():
            buffer.clear()
        self.state.live_busy = True
        self.state_changed.emit(self.state)
        self.message.emit("Synchronizing and starting live preview…")
        self._command(
            "start_live",
            {"sides": list(sides), "sync_count": 5, "lead_time_s": 1.0},
            self._live_started,
            on_error=self._live_failed,
        )

    def stop_live(self) -> None:
        if not self.state.live or self.state.live_busy:
            return
        self.state.live_busy = True
        self.state_changed.emit(self.state)
        self.message.emit("Stopping live preview…")
        self._command(
            "stop_live",
            {},
            self._live_stopped,
            on_error=self._live_failed,
        )

    def refresh_status(self) -> None:
        if not self.client.ready:
            self.client.connect_to_daemon()
            return
        self._command("status", {}, self._apply_status, quiet=True)

    def refresh_sessions(self) -> None:
        self._command("list_sessions", {}, self._on_sessions, quiet=True)

    def set_session_folder(self, folder_path: str | Path) -> None:
        path_str = str(Path(folder_path).resolve())
        self.state.journal_root = path_str
        settings = load_gui_settings()
        settings["session_folder"] = path_str
        save_gui_settings(settings)
        self._command(
            "set_journal_root",
            {"journal_root": path_str},
            lambda _result: (
                self.message.emit(f"Session folder updated: {path_str}"),
                self.refresh_status(),
                self.refresh_sessions(),
            ),
        )

    def export_session(self, session_id: str, output_path: str) -> None:
        self._command(
            "export_session",
            {"session_id": session_id, "output_path": output_path},
            lambda result: self.message.emit(
                f"CSV exported: {result.get('output_path', output_path)}"
            ),
        )

    def export_sessions(
        self, sessions: list[dict[str, Any]], target_directory: str | Path
    ) -> list[str]:
        target_dir = Path(target_directory)
        target_dir.mkdir(parents=True, exist_ok=True)
        exported_paths: list[str] = []
        for item in sessions:
            session_id = str(item.get("session_id", "")).strip()
            if not session_id:
                continue
            topic = sanitize_name(item.get("topic") or "General")
            trial = item.get("trial_number", 1)
            trial_str = f"Trial{trial}" if str(trial).isdigit() else sanitize_name(str(trial))
            athlete = sanitize_name(item.get("athlete") or "")
            topic_folder = target_dir / topic
            topic_folder.mkdir(parents=True, exist_ok=True)
            if athlete:
                output_file = topic_folder / f"{topic}_{trial_str}_{athlete}.csv"
            else:
                output_file = topic_folder / f"{topic}_{trial_str}.csv"
            self.export_session(session_id, str(output_file))
            exported_paths.append(str(output_file))
        if exported_paths:
            self.message.emit(
                f"Exporting {len(exported_paths)} session CSV(s) to {target_dir}"
            )
        return exported_paths

    def load_session_data(self, session_id: str) -> dict[str, Any]:
        root = Path(self.state.journal_root or (Path.home() / "Documents" / "WheelAthlete" / "PC Sessions"))
        journal_path = root / f"{session_id}.waj"
        manifest_path = root / f"{session_id}.summary.json"
        meta: dict[str, Any] = {}
        if manifest_path.exists():
            try:
                meta = json.loads(manifest_path.read_text(encoding="utf-8"))
            except Exception:
                pass

        samples_l: list[dict[str, float]] = []
        samples_r: list[dict[str, float]] = []
        gap_events: list[dict[str, Any]] = []

        accel_scale_l = self.state.boards["L"].accel_scale if self.state.boards["L"].accel_scale not in (1.0, 0.0) else (16.0 / 32768.0)
        gyro_scale_l = self.state.boards["L"].gyro_scale if self.state.boards["L"].gyro_scale not in (1.0, 0.0) else (2000.0 / 32768.0)
        accel_scale_r = self.state.boards["R"].accel_scale if self.state.boards["R"].accel_scale not in (1.0, 0.0) else (16.0 / 32768.0)
        gyro_scale_r = self.state.boards["R"].gyro_scale if self.state.boards["R"].gyro_scale not in (1.0, 0.0) else (2000.0 / 32768.0)

        if journal_path.exists():
            try:
                from tools.pc_acquisition.journal import JournalReader, RecordKind
                records = JournalReader(journal_path).read_all()
                first_t_ns = None
                for record in records:
                    if record.kind is RecordKind.SESSION_META and record.json_value:
                        meta.update(record.json_value)
                        if "accel_scale" in record.json_value:
                            accel_scale_l = accel_scale_r = float(record.json_value["accel_scale"])
                        if "gyro_scale" in record.json_value:
                            gyro_scale_l = gyro_scale_r = float(record.json_value["gyro_scale"])
                    elif record.kind is RecordKind.SAMPLE and record.sample is not None:
                        rec = record.sample
                        if first_t_ns is None:
                            first_t_ns = rec.arrival_ns
                        t_sec = max(0.0, (rec.arrival_ns - first_t_ns) / 1_000_000_000.0)
                        side_str = rec.side.value
                        accel_scale = accel_scale_l if side_str == "L" else accel_scale_r
                        gyro_scale = gyro_scale_l if side_str == "L" else gyro_scale_r
                        entry = {
                            "t": t_sec,
                            "seq": rec.sample.seq,
                            "ax": rec.sample.ax * accel_scale,
                            "ay": rec.sample.ay * accel_scale,
                            "az": rec.sample.az * accel_scale,
                            "gx": rec.sample.gx * gyro_scale,
                            "gy": rec.sample.gy * gyro_scale,
                            "gz": rec.sample.gz * gyro_scale,
                        }
                        if side_str == "L":
                            samples_l.append(entry)
                        else:
                            samples_r.append(entry)
                        if rec.missing_before > 0 or rec.sequence_class in ("gap", "out_of_order"):
                            gap_events.append({
                                "side": side_str,
                                "time_s": t_sec,
                                "seq": rec.sample.seq,
                                "missing": rec.missing_before,
                                "reason": rec.sequence_class,
                            })
            except Exception as exc:
                self.daemon_log.emit(f"Failed to read journal {journal_path}: {exc}")

        csv_path = root / f"{session_id}.csv"
        if not samples_l and not samples_r and csv_path.exists():
            try:
                with csv_path.open("r", encoding="utf-8") as handle:
                    reader = csv.DictReader(handle)
                    first_ns = None
                    for row in reader:
                        arr_ns = int(row.get("timestamp_pc_monotonic_ns", 0) or 0)
                        if first_ns is None:
                            first_ns = arr_ns
                        t_sec = max(0.0, (arr_ns - first_ns) / 1_000_000_000.0)
                        side_str = row.get("wheel", "L")
                        accel_scale = accel_scale_l if side_str == "L" else accel_scale_r
                        gyro_scale = gyro_scale_l if side_str == "L" else gyro_scale_r
                        seq = int(row.get("seq", 0) or 0)
                        missing = int(row.get("missing_before", 0) or 0)
                        seq_class = row.get("sequence_class", "contiguous")
                        entry = {
                            "t": t_sec,
                            "seq": seq,
                            "ax": float(row.get("ax_raw", 0) or 0) * accel_scale,
                            "ay": float(row.get("ay_raw", 0) or 0) * accel_scale,
                            "az": float(row.get("az_raw", 0) or 0) * accel_scale,
                            "gx": float(row.get("gx_raw", 0) or 0) * gyro_scale,
                            "gy": float(row.get("gy_raw", 0) or 0) * gyro_scale,
                            "gz": float(row.get("gz_raw", 0) or 0) * gyro_scale,
                        }
                        if side_str == "L":
                            samples_l.append(entry)
                        else:
                            samples_r.append(entry)
                        if missing > 0 or seq_class in ("gap", "out_of_order"):
                            gap_events.append({
                                "side": side_str,
                                "time_s": t_sec,
                                "seq": seq,
                                "missing": missing,
                                "reason": seq_class,
                            })
            except Exception as exc:
                self.daemon_log.emit(f"Failed to read CSV {csv_path}: {exc}")

        duration_s = meta.get("duration_s")
        if duration_s is None:
            max_tl = samples_l[-1]["t"] if samples_l else 0.0
            max_tr = samples_r[-1]["t"] if samples_r else 0.0
            duration_s = max(max_tl, max_tr)

        return {
            "session_id": session_id,
            "topic": meta.get("topic", ""),
            "trial_number": meta.get("trial_number", ""),
            "athlete": meta.get("athlete", ""),
            "quality": meta.get("quality", "GOOD"),
            "sample_rate_hz": meta.get("sample_rate_hz", 100),
            "duration_s": duration_s,
            "samples": {"L": samples_l, "R": samples_r},
            "gaps": gap_events,
            "total_missing_samples": sum(g.get("missing", 1) for g in gap_events),
        }

    def delete_session(self, session_id: str) -> None:
        self._command(
            "delete_session",
            {"session_id": session_id},
            lambda _result: (
                self.message.emit("Recording deleted"),
                self.refresh_sessions(),
            ),
        )

    def delete_sessions(self, session_ids: list[str]) -> None:
        remaining = list(session_ids)
        if not remaining:
            return

        def delete_next() -> None:
            if not remaining:
                self.message.emit(f"Deleted {len(session_ids)} recording(s)")
                self.refresh_sessions()
                return
            s_id = remaining.pop(0)
            self._command(
                "delete_session",
                {"session_id": s_id},
                lambda _result: delete_next(),
                on_error=lambda _err: delete_next(),
            )

        delete_next()

    def export_diagnostics(self, output_path: str) -> None:
        self._command(
            "diagnostic_report",
            {"output_path": output_path},
            lambda result: self.message.emit(
                f"Diagnostics exported: {result.get('output_path', output_path)}"
            ),
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
        if self.state.recording or self.state.recording_starting:
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

        self.state.recording_starting = True
        self.state.countdown = None
        self.state_changed.emit(self.state)

        # Configuration acknowledgements are required before START. This keeps
        # QC's configured-rate metadata aligned with the firmware state.
        pending = list(sides)

        def configure_next() -> None:
            if not pending:
                payload = dict(metadata)
                payload["sides"] = list(sides)
                payload.setdefault("sync_count", 12)
                payload.setdefault("lead_time_s", 5.0)
                payload.setdefault("ack_timeout_s", 1.0)
                self._command(
                    "start_record",
                    payload,
                    self._record_started,
                    on_error=self._record_failed,
                )
                return
            side = pending.pop(0)
            self._command(
                "configure",
                {"side": side, "sample_rate_hz": rate},
                lambda _result: configure_next(),
                on_error=self._record_failed,
            )

        def begin() -> None:
            for buffer in self._preview.values():
                buffer.clear()
            configure_next()

        if self.state.live:
            self.state.live_busy = True
            self.state_changed.emit(self.state)

            def stopped_for_record(_result: dict[str, Any]) -> None:
                self.state.live = False
                self.state.live_sides = ()
                self.state.live_busy = False
                self.state_changed.emit(self.state)
                begin()

            self._command(
                "stop_live",
                {},
                stopped_for_record,
                on_error=self._record_failed,
            )
        else:
            begin()

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
        on_error: Any | None = None,
        quiet: bool = False,
    ) -> None:
        if not self.client.ready:
            if not quiet:
                message = "Acquisition daemon is not ready"
                if on_error is not None:
                    on_error(message)
                self.command_error.emit(command, message)
            return
        try:
            self.client.send_command(
                command,
                payload,
                on_success=callback,
                on_error=(lambda _message: None) if quiet else on_error,
            )
        except (RuntimeError, ValueError) as exc:
            if not quiet:
                if on_error is not None:
                    on_error(str(exc))
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
        self._finish_scan()
        self.message.emit(f"Found {len(self.scan_results)} WheelAthlete device(s)")

    def _finish_scan(self) -> None:
        self.state.scanning = False
        self.state_changed.emit(self.state)

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
        self.state.recording_starting = False
        self.state.countdown = None
        self.state.session_id = str(result.get("session_id")) if result.get("session_id") else None
        self.state_changed.emit(self.state)
        self.message.emit("Recording started with synchronized device clocks")
        self.refresh_status()

    def _record_stopped(self, result: dict[str, Any]) -> None:
        self.state.recording = False
        self.state.recording_starting = False
        self.state.countdown = None
        self.state.session_id = None
        self.state_changed.emit(self.state)
        self.recording_finished.emit(result)
        self.refresh_status()
        self.refresh_sessions()

    def _record_failed(self, _message: str) -> None:
        self.state.recording_starting = False
        self.state.countdown = None
        self.state.live_busy = False
        self.state_changed.emit(self.state)
        self.refresh_status()

    def _live_started(self, result: dict[str, Any]) -> None:
        self.state.live = True
        self.state.live_sides = tuple(str(side) for side in result.get("sides", []))
        self.state.live_busy = False
        self.state_changed.emit(self.state)
        self.message.emit("Live preview is running")
        self.refresh_status()

    def _live_stopped(self, _result: dict[str, Any]) -> None:
        self.state.live = False
        self.state.live_sides = ()
        self.state.live_busy = False
        self.state_changed.emit(self.state)
        self.message.emit("Live preview stopped")
        self.refresh_status()

    def _live_failed(self, _message: str) -> None:
        self.state.live_busy = False
        self.state_changed.emit(self.state)
        self.refresh_status()

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
            if state == "countdown":
                self.state.recording_starting = True
                self.state.countdown = max(1, int(payload.get("seconds", 5)))
            elif state in {"started", "recording"}:
                self.state.recording = True
                self.state.recording_starting = False
                self.state.countdown = None
            elif state in {"stopped", "finalized"}:
                self.state.recording = False
                self.state.recording_starting = False
                self.state.countdown = None
            self.state_changed.emit(self.state)
        elif event_type == "live_state":
            self.state.live = bool(payload.get("live"))
            self.state.live_sides = tuple(str(side) for side in payload.get("sides", []))
            self.state.live_busy = False
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
                firmware="1.8.0",
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
        self.sessions = [
            {
                "session_id": "demo_sprint_01",
                "session_dir": str(Path(self.state.journal_root) / "demo_sprint_01"),
                "athlete": "Athlete A",
                "topic": "Sprint",
                "trial_number": 1,
                "sample_rate_hz": 100,
                "quality": "GOOD",
                "duration_s": 15.2,
                "sample_counts": {"L": 1520, "R": 1520},
                "tags": ["100m", "accel"],
                "notes": "Fast sprint demo",
            },
            {
                "session_id": "demo_sprint_02",
                "session_dir": str(Path(self.state.journal_root) / "demo_sprint_02"),
                "athlete": "Athlete A",
                "topic": "Sprint",
                "trial_number": 2,
                "sample_rate_hz": 100,
                "quality": "GOOD",
                "duration_s": 14.8,
                "sample_counts": {"L": 1480, "R": 1480},
                "tags": ["100m", "accel"],
                "notes": "Second sprint demo",
            },
            {
                "session_id": "demo_endurance_01",
                "session_dir": str(Path(self.state.journal_root) / "demo_endurance_01"),
                "athlete": "Athlete B",
                "topic": "Endurance",
                "trial_number": 1,
                "sample_rate_hz": 50,
                "quality": "GOOD",
                "duration_s": 60.0,
                "sample_counts": {"L": 3000, "R": 3000},
                "tags": ["aerobic"],
                "notes": "Steady pace demo",
            },
        ]

    def start(self) -> None:
        self._timer.start()
        self.state_changed.emit(self.state)
        self.scan_results = [
            {"device_id": "DEMO-L", "name": "WheelAthlete-L", "rssi": -46},
            {"device_id": "DEMO-R", "name": "WheelAthlete-R", "rssi": -49},
        ]
        self.scan_results_changed.emit(list(self.scan_results))
        self.sessions_changed.emit(list(self.sessions))

    def close(self) -> None:
        self._timer.stop()

    def scan(self) -> None:
        self.scan_results_changed.emit(list(self.scan_results))

    def connect_device(self, device_id: str) -> None:
        self.message.emit(f"Demo device already connected: {device_id}")

    def connect_devices(self, device_ids: list[str]) -> None:
        self.message.emit(f"Demo devices already connected: {len(device_ids)}")


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

    def start_live(self) -> None:
        self.state.live = True
        self.state.live_sides = self.state.connected_sides()
        self.state_changed.emit(self.state)
        self.message.emit("DEMO live preview started")

    def stop_live(self) -> None:
        self.state.live = False
        self.state.live_sides = ()
        self.state_changed.emit(self.state)
        self.message.emit("DEMO live preview stopped")

    def refresh_status(self) -> None:
        self.state_changed.emit(self.state)

    def refresh_sessions(self) -> None:
        self.sessions_changed.emit(list(self.sessions))

    def set_session_folder(self, folder_path: str | Path) -> None:
        path_str = str(Path(folder_path).resolve())
        self.state.journal_root = path_str
        settings = load_gui_settings()
        settings["session_folder"] = path_str
        save_gui_settings(settings)
        self.message.emit(f"Demo session folder updated: {path_str}")
        self.state_changed.emit(self.state)
        self.sessions_changed.emit(list(self.sessions))

    def export_session(self, session_id: str, output_path: str) -> None:
        out = Path(output_path)
        out.parent.mkdir(parents=True, exist_ok=True)
        with out.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.writer(handle)
            writer.writerow([
                "session_id", "wheel", "seq", "timestamp_device_us",
                "timestamp_pc_monotonic_ns", "ax_raw", "ay_raw", "az_raw",
                "gx_raw", "gy_raw", "gz_raw"
            ])
            for i in range(20):
                writer.writerow([
                    session_id, "L" if i % 2 == 0 else "R", i, i * 10000,
                    time.monotonic_ns(), 100, 200, 16000, 10, 20, 30
                ])
        self.message.emit(f"CSV exported: {output_path}")

    def export_sessions(
        self, sessions: list[dict[str, Any]], target_directory: str | Path
    ) -> list[str]:
        target_dir = Path(target_directory)
        target_dir.mkdir(parents=True, exist_ok=True)
        exported: list[str] = []
        for item in sessions:
            session_id = str(item.get("session_id", "")).strip()
            if not session_id:
                continue
            topic = sanitize_name(item.get("topic") or "General")
            trial = item.get("trial_number", 1)
            trial_str = f"Trial{trial}" if str(trial).isdigit() else sanitize_name(str(trial))
            athlete = sanitize_name(item.get("athlete") or "")
            topic_folder = target_dir / topic
            topic_folder.mkdir(parents=True, exist_ok=True)
            if athlete:
                out_file = topic_folder / f"{topic}_{trial_str}_{athlete}.csv"
            else:
                out_file = topic_folder / f"{topic}_{trial_str}.csv"
            self.export_session(session_id, str(out_file))
            exported.append(str(out_file))
        self.message.emit(f"Demo exported {len(exported)} session CSV(s) to {target_dir}")
        return exported

    def load_session_data(self, session_id: str) -> dict[str, Any]:
        match = next((s for s in self.sessions if s.get("session_id") == session_id), None)
        topic = match.get("topic", "General") if match else "General"
        trial = match.get("trial_number", 1) if match else 1
        athlete = match.get("athlete", "Athlete") if match else "Athlete"
        duration_s = float(match.get("duration_s", 15.0) if match else 15.0)
        rate_hz = int(match.get("sample_rate_hz", 100) if match else 100)
        quality = match.get("quality", "GOOD") if match else "GOOD"

        total_samples = max(20, int(duration_s * rate_hz))
        dt = 1.0 / rate_hz

        samples_l: list[dict[str, float]] = []
        samples_r: list[dict[str, float]] = []
        gaps: list[dict[str, Any]] = []

        has_demo_gap = "02" in session_id or "gap" in session_id.lower()
        gap_idx = total_samples // 2 if has_demo_gap else -1

        import math
        for i in range(total_samples):
            t = i * dt
            if has_demo_gap and i == gap_idx:
                gaps.append({
                    "side": "L",
                    "time_s": round(t, 2),
                    "seq": i,
                    "missing": 3,
                    "reason": "gap",
                })
                continue

            phase = 2 * math.pi * 1.5 * t
            samples_l.append({
                "t": t,
                "seq": i,
                "ax": math.sin(phase) * 0.8 + 0.1,
                "ay": math.cos(phase * 1.2) * 0.4,
                "az": 0.98 + math.sin(phase * 0.5) * 0.2,
                "gx": math.sin(phase * 2) * 80.0,
                "gy": math.cos(phase * 2) * 45.0,
                "gz": math.sin(phase) * 120.0,
            })
            samples_r.append({
                "t": t,
                "seq": i,
                "ax": math.sin(phase + 0.3) * 0.85 + 0.1,
                "ay": math.cos(phase * 1.2 + 0.3) * 0.42,
                "az": 0.98 + math.sin(phase * 0.5 + 0.3) * 0.22,
                "gx": math.sin(phase * 2 + 0.3) * 78.0,
                "gy": math.cos(phase * 2 + 0.3) * 44.0,
                "gz": math.sin(phase + 0.3) * 118.0,
            })

        return {
            "session_id": session_id,
            "topic": topic,
            "trial_number": trial,
            "athlete": athlete,
            "quality": "DEGRADED" if gaps else quality,
            "sample_rate_hz": rate_hz,
            "duration_s": duration_s,
            "samples": {"L": samples_l, "R": samples_r},
            "gaps": gaps,
            "total_missing_samples": sum(g.get("missing", 1) for g in gaps),
        }

    def delete_session(self, session_id: str) -> None:
        self.sessions = [s for s in self.sessions if s.get("session_id") != session_id]
        self.message.emit("Demo recording deleted")
        self.refresh_sessions()

    def delete_sessions(self, session_ids: list[str]) -> None:
        ids_to_del = set(session_ids)
        self.sessions = [s for s in self.sessions if s.get("session_id") not in ids_to_del]
        self.message.emit(f"Demo deleted {len(ids_to_del)} recording(s)")
        self.refresh_sessions()

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
        duration = max(0.1, (time.monotonic_ns() - self._started_ns) / 1e9)
        new_session = {
            "session_id": self.state.session_id or f"DEMO-{uuid.uuid4().hex[:8]}",
            "athlete": "Athlete",
            "topic": "Sprint",
            "trial_number": len(self.sessions) + 1,
            "sample_rate_hz": 100,
            "duration_s": duration,
            "quality": "GOOD",
            "sample_counts": {"L": int(duration * 100), "R": int(duration * 100)},
        }
        self.sessions.insert(0, new_session)
        self.state.session_id = None
        self.state_changed.emit(self.state)
        self.recording_finished.emit(
            {
                "quality": "GOOD",
                "duration_s": duration,
                "reasons": [],
                "demo": True,
            }
        )
        self.refresh_sessions()

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
