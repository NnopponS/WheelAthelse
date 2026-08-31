from __future__ import annotations

import dataclasses
import json
import os
import struct
import time
from pathlib import Path
from typing import Any, Callable

from .clock_sync import ClockModel
from .control import CMD_SET_RANGE, CMD_SET_RATE
from .engine import DualBoardEngine
from .journal import JournalReader, JournalRecorder, RecordKind, recover_open_journal
from .models import IngestionMetrics, ReceivedSample, WheelSide
from .qc import BoardQcInput, SessionQcInput, evaluate_session_qc
from .transport import BleTransport
from .uuids import BATTERY_LEVEL_UUID, CONFIG_UUID, CONTROL_UUID, INFO_UUID
from .lifecycle import StartResult, SyncLifecycleController


EventSink = Callable[[str, dict[str, Any]], None]


def _side(value: Any) -> WheelSide:
    if value in ("L", "left", "LEFT"):
        return WheelSide.LEFT
    if value in ("R", "right", "RIGHT"):
        return WheelSide.RIGHT
    raise ValueError(f"invalid wheel side: {value!r}")


def _parse_config(payload: bytes) -> dict[str, Any]:
    if len(payload) < 27:
        raise ValueError(f"Config characteristic must be at least 27 bytes, got {len(payload)}")
    name = payload[:24].split(b"\x00", 1)[0].decode("ascii", errors="replace")
    wheel = payload[24]
    if wheel not in (0x4C, 0x52):
        raise ValueError(f"invalid config wheel id 0x{wheel:02X}")
    rate_hz = struct.unpack_from("<H", payload, 25)[0]
    return {"name": name, "wheel": chr(wheel), "sample_rate_hz": rate_hz}


def _parse_info(payload: bytes) -> dict[str, Any]:
    if len(payload) != 16:
        raise ValueError(f"Info characteristic must be 16 bytes, got {len(payload)}")
    side_byte, major, minor, patch, accel_range, gyro_range = struct.unpack_from(
        "<BBBBBB", payload, 0
    )
    if side_byte not in (0x4C, 0x52):
        raise ValueError(f"invalid wheel id 0x{side_byte:02X}")
    accel_scale, gyro_scale = struct.unpack_from("<ff", payload, 6)
    return {
        "side": chr(side_byte),
        "firmware": f"{major}.{minor}.{patch}",
        "firmware_major": major,
        "firmware_minor": minor,
        "firmware_patch": patch,
        "accel_range": accel_range,
        "gyro_range": gyro_range,
        "accel_scale": accel_scale,
        "gyro_scale": gyro_scale,
        "hardware_model": payload[14],
        "capabilities": payload[15],
    }


def _metrics_delta(current: IngestionMetrics, baseline: IngestionMetrics) -> IngestionMetrics:
    return IngestionMetrics(
        notifications_received=current.notifications_received - baseline.notifications_received,
        samples_received=current.samples_received - baseline.samples_received,
        malformed_packets=current.malformed_packets - baseline.malformed_packets,
        sequence_gaps=current.sequence_gaps - baseline.sequence_gaps,
        duplicate_samples=current.duplicate_samples - baseline.duplicate_samples,
        out_of_order_samples=current.out_of_order_samples - baseline.out_of_order_samples,
        queue_high_water=current.queue_high_water,
        queue_overflow_faults=current.queue_overflow_faults - baseline.queue_overflow_faults,
    )


class AcquisitionService:
    """Command-oriented owner of the headless research acquisition pipeline."""

    def __init__(
        self,
        transport: BleTransport,
        *,
        journal_root: Path | str,
        event_sink: EventSink | None = None,
    ) -> None:
        self.transport = transport
        self.journal_root = Path(journal_root)
        self.journal_root.mkdir(parents=True, exist_ok=True)
        self._event_sink = event_sink
        self._journal: JournalRecorder | None = None
        self._record_sides: tuple[WheelSide, ...] = ()
        self._record_started_ns: int | None = None
        self._start_result: StartResult | None = None
        self._metric_baseline: dict[WheelSide, IngestionMetrics] = {}
        self._device_info: dict[WheelSide, dict[str, Any]] = {}
        self._last_preview: dict[WheelSide, ReceivedSample] = {}
        self._scan_cache: dict[str, dict[str, Any]] = {}
        self._status_rate_baseline: dict[WheelSide, tuple[int, int, int]] = {}
        self._record_metadata: dict[str, Any] | None = None
        self.engine = DualBoardEngine(
            transport,
            sample_sink=self._on_sample,
            preview_sink=self._on_preview,
        )
        self.lifecycle = SyncLifecycleController(self.engine, transport)
        self._started = False

    def set_event_sink(self, sink: EventSink | None) -> None:
        self._event_sink = sink

    async def start(self) -> None:
        if self._started:
            return
        await self.engine.start()
        self._started = True

    async def close(self) -> None:
        if self._journal is not None:
            self._journal.abort_without_finalize_for_test()
            self._journal = None
        if self._started:
            await self.engine.stop()
            self._started = False

    def _emit(self, event_type: str, payload: dict[str, Any]) -> None:
        if self._event_sink is not None:
            self._event_sink(event_type, payload)

    def _on_sample(self, received: ReceivedSample) -> None:
        journal = self._journal
        if journal is not None and not journal.submit_sample(received):
            self._emit(
                "error",
                {
                    "code": "journal_queue_overflow",
                    "message": journal.fatal_fault.message if journal.fatal_fault else "journal overflow",
                },
            )

    def _on_preview(self, received: ReceivedSample) -> None:
        self._last_preview[received.side] = received
        sample = received.sample
        self._emit(
            "sample_preview",
            {
                "side": received.side.value,
                "seq": sample.seq,
                "timestamp_device_us": sample.t_device_us,
                "timestamp_pc_monotonic_ns": received.arrival_ns,
                "ax_raw": sample.ax,
                "ay_raw": sample.ay,
                "az_raw": sample.az,
                "gx_raw": sample.gx,
                "gy_raw": sample.gy,
                "gz_raw": sample.gz,
            },
        )

    async def handle_command(self, command: str, payload: dict[str, Any]) -> dict[str, Any]:
        await self.start()
        handlers = {
            "scan": self._cmd_scan,
            "connect": self._cmd_connect,
            "disconnect": self._cmd_disconnect,
            "configure": self._cmd_configure,
            "sync": self._cmd_sync,
            "arm": self._cmd_arm,
            "scheduled_start": self._cmd_scheduled_start,
            "stop": self._cmd_stop,
            "status": self._cmd_status,
            "start_record": self._cmd_start_record,
            "end_record": self._cmd_end_record,
            "recover": self._cmd_recover,
            "list_sessions": self._cmd_list_sessions,
            "export_session": self._cmd_export_session,
            "diagnostic_report": self._cmd_diagnostic_report,
        }
        try:
            handler = handlers[command]
        except KeyError as exc:
            raise ValueError(f"unknown command {command!r}") from exc
        return await handler(payload)

    async def _cmd_scan(self, payload: dict[str, Any]) -> dict[str, Any]:
        timeout_s = float(payload.get("timeout_s", 5.0))
        if not 0.1 <= timeout_s <= 30.0:
            raise ValueError("scan timeout_s must be between 0.1 and 30")
        devices = await self.transport.scan(timeout_s)
        result = [dataclasses.asdict(device) for device in devices]
        self._scan_cache = {str(device["device_id"]): dict(device) for device in result}
        for device in result:
            self._emit("device_found", device)
        return {"devices": result}

    async def _cmd_connect(self, payload: dict[str, Any]) -> dict[str, Any]:
        device_id = str(payload["device_id"])
        await self.transport.connect(device_id)
        try:
            info = _parse_info(await self.transport.read(device_id, INFO_UUID))
            side = _side(info["side"])
            existing = self.engine.device_id(side)
            if existing is not None and existing != device_id:
                raise RuntimeError(f"{side.value} wheel is already connected as {existing}")
            if existing is None:
                await self.engine.connect(side, device_id)
            info = dict(info)
            info["device_id"] = device_id
            info["mtu"] = self.transport.negotiated_mtu(device_id)
            candidate = self._scan_cache.get(device_id, {})
            info["advertised_name"] = candidate.get("name")
            info["rssi"] = candidate.get("rssi")
            try:
                config = _parse_config(await self.transport.read(device_id, CONFIG_UUID))
            except Exception:
                config = {}
            info.update(config)
            try:
                battery = await self.transport.read(device_id, BATTERY_LEVEL_UUID)
                info["battery_percent"] = int(battery[0]) if battery else None
            except Exception:
                info["battery_percent"] = None
            info.setdefault("sample_rate_hz", 100)
            info.setdefault("name", info.get("advertised_name") or f"WheelAthlete-{side.value}")
            self._device_info[side] = info
            self._emit("connection_state", {**info, "state": "connected"})
            return info
        except BaseException:
            if all(self.engine.device_id(side) != device_id for side in WheelSide):
                await self.transport.disconnect(device_id)
            raise

    async def _cmd_disconnect(self, payload: dict[str, Any]) -> dict[str, Any]:
        side = _side(payload["side"])
        device_id = self.engine.device_id(side)
        await self.engine.disconnect(side)
        self._device_info.pop(side, None)
        self._emit(
            "connection_state",
            {"side": side.value, "device_id": device_id, "state": "disconnected"},
        )
        return {"side": side.value, "disconnected": True}

    async def _cmd_configure(self, payload: dict[str, Any]) -> dict[str, Any]:
        side = _side(payload["side"])
        device_id = self._require_device(side)
        if "sample_rate_hz" in payload:
            rate = int(payload["sample_rate_hz"])
            if rate not in (50, 100, 200):
                raise ValueError("sample_rate_hz must be 50, 100, or 200")
            await self.transport.write(
                device_id, CONTROL_UUID, struct.pack("<BH", CMD_SET_RATE, rate), response=True
            )
            if side in self._device_info:
                self._device_info[side]["sample_rate_hz"] = rate
        if "accel_range" in payload or "gyro_range" in payload:
            accel = int(payload.get("accel_range", self._device_info.get(side, {}).get("accel_range", 1)))
            gyro = int(payload.get("gyro_range", self._device_info.get(side, {}).get("gyro_range", 3)))
            if not (0 <= accel <= 3 and 0 <= gyro <= 3):
                raise ValueError("accel_range and gyro_range must be 0..3")
            await self.transport.write(
                device_id,
                CONTROL_UUID,
                struct.pack("<BBB", CMD_SET_RANGE, accel, gyro),
                response=True,
            )
            # SET_RANGE changes both the range codes and the raw->physical
            # conversion scales exposed by the Info characteristic. Re-read
            # that characteristic before reporting success so every UI and
            # exported metadata snapshot uses the firmware-authoritative scale
            # immediately rather than a stale value from connection time.
            refreshed = _parse_info(await self.transport.read(device_id, INFO_UUID))
            if _side(refreshed["side"]) is not side:
                raise RuntimeError(
                    f"Info wheel changed after SET_RANGE: expected {side.value}, "
                    f"got {refreshed['side']}"
                )
            if side in self._device_info:
                self._device_info[side].update(refreshed)
        return {"side": side.value, "configured": True}

    async def _cmd_sync(self, payload: dict[str, Any]) -> dict[str, Any]:
        side = _side(payload["side"])
        count = int(payload.get("count", 10))
        model = await self.lifecycle.synchronize(side, count=count)
        result = self._clock_payload(side, model)
        self._emit("sync_status", result)
        return result

    async def _cmd_arm(self, payload: dict[str, Any]) -> dict[str, Any]:
        sides = self._selected_sides(payload)
        if not sides:
            raise RuntimeError("no wheels are connected")
        # IMU and Sync CCCDs are already subscribed by DualBoardEngine.connect;
        # arm is an explicit lifecycle checkpoint, not a second subscription.
        return {"armed": [side.value for side in sides]}

    async def _cmd_scheduled_start(self, payload: dict[str, Any]) -> dict[str, Any]:
        sides = self._selected_sides(payload)
        await self.engine.reset_sequences(sides)
        result = await self.lifecycle.scheduled_start(
            sides,
            lead_time_s=float(payload.get("lead_time_s", 3.0)),
            ack_timeout_s=float(payload.get("ack_timeout_s", 1.0)),
        )
        value = self._start_payload(result)
        self._emit("recording_state", {"state": "started", **value})
        return value

    async def _cmd_stop(self, payload: dict[str, Any]) -> dict[str, Any]:
        sides = self._selected_sides(payload)
        result = await self.lifecycle.stop_all(sides)
        value = {
            side.value: {
                "acknowledged": item.acknowledged,
                "write_attempts": item.write_attempts,
                "error": item.error,
            }
            for side, item in result.items()
        }
        self._emit("recording_state", {"state": "stopped", "wheels": value})
        return {"wheels": value}

    async def _cmd_status(self, payload: dict[str, Any]) -> dict[str, Any]:
        del payload
        return self.status()

    async def _cmd_start_record(self, payload: dict[str, Any]) -> dict[str, Any]:
        if self._journal is not None:
            raise RuntimeError("a recording is already active")
        sides = self._selected_sides(payload)
        if not sides:
            raise RuntimeError("no wheels are connected")
        session_id = payload.get("session_id")
        journal = JournalRecorder(self.journal_root, session_id=session_id)
        self._journal = journal
        self._record_sides = sides
        self._metric_baseline = {
            side: dataclasses.replace(self.engine.metrics(side)) for side in sides
        }
        acceptance = payload.get("acceptance")
        if acceptance is not None and not isinstance(acceptance, dict):
            raise ValueError("acceptance metadata must be an object")
        metadata = {
            "athlete": str(payload.get("athlete", "")),
            "topic": str(payload.get("topic", "")),
            "trial_number": int(payload.get("trial_number", 1)),
            "notes": str(payload.get("notes", "")),
            "sample_rate_hz": int(payload.get("sample_rate_hz", 100)),
            "protocol_template_id": payload.get("protocol_template_id"),
            "tags": [str(item) for item in payload.get("tags", [])],
            "acceptance": dict(acceptance) if acceptance is not None else None,
            "boards": {side.value: self._device_info.get(side, {}) for side in sides},
        }
        journal.append_metadata(metadata)
        self._record_metadata = dict(metadata)
        self._record_metadata["session_id"] = journal.session_id
        try:
            sync_count = int(payload.get("sync_count", 10))
            for side in sides:
                model = await self.lifecycle.synchronize(side, count=sync_count)
                journal.append_json(RecordKind.SYNC, self._clock_payload(side, model))
            # XIAO firmware resets seq to zero on each START; mirror that epoch
            # boundary after sync traffic has drained and before scheduling T0.
            await self.engine.reset_sequences(sides)
            start = await self.lifecycle.scheduled_start(
                sides,
                lead_time_s=float(payload.get("lead_time_s", 3.0)),
                ack_timeout_s=float(payload.get("ack_timeout_s", 1.0)),
            )
            self._start_result = start
            self._record_started_ns = start.pc_start_ns
            journal.append_json(RecordKind.EVENT, {"type": "START", **self._start_payload(start)})
            value = {
                "session_id": journal.session_id,
                "journal_path": str(journal.open_path),
                **self._start_payload(start),
            }
            self._emit("recording_state", {"state": "recording", **value})
            return value
        except BaseException as exc:
            journal.append_json(RecordKind.ERROR, {"type": "start_failure", "message": str(exc)})
            journal.abort_without_finalize_for_test()
            self._journal = None
            self._record_sides = ()
            self._record_started_ns = None
            self._start_result = None
            self._record_metadata = None
            raise

    async def _cmd_end_record(self, payload: dict[str, Any]) -> dict[str, Any]:
        del payload
        journal = self._journal
        if journal is None:
            raise RuntimeError("no recording is active")
        sides = self._record_sides
        stop_results = await self.lifecycle.stop_all(sides)
        await self.engine.join()
        end_ns = time.monotonic_ns()
        duration_s = max(
            0.001,
            (end_ns - (self._record_started_ns or end_ns)) / 1_000_000_000,
        )
        for side, stop_result in stop_results.items():
            health = stop_result.health
            if health is not None:
                journal.append_json(
                    RecordKind.HEALTH,
                    {"side": side.value, **dataclasses.asdict(health)},
                )
            journal.append_json(
                RecordKind.EVENT,
                {
                    "type": "STOP",
                    "side": side.value,
                    "acknowledged": stop_result.acknowledged,
                    "write_attempts": stop_result.write_attempts,
                    "error": stop_result.error,
                },
            )

        # Post-stop clock refinement is best-effort and never changes already
        # journaled raw device timestamps. It improves the final mapping/drift
        # metadata when the BLE link remains healthy.
        for side in sides:
            if self.engine.device_id(side) is None:
                continue
            try:
                model = await self.lifecycle.synchronize(side, count=3)
                journal.append_json(
                    RecordKind.SYNC,
                    {"phase": "post_stop", **self._clock_payload(side, model)},
                )
            except Exception as exc:
                journal.append_json(
                    RecordKind.ERROR,
                    {"type": "post_stop_sync_failure", "side": side.value, "message": str(exc)},
                )

        # QC must observe the authoritative on-disk writer after every sample
        # accepted by the journal queue has either committed or produced a
        # fatal writer fault. Otherwise a fast STOP could inspect stale writer
        # counters and accidentally certify an incomplete session.
        journal.wait_until_idle()

        board_qc: list[BoardQcInput] = []
        for side in sides:
            current = self.engine.metrics(side)
            baseline = self._metric_baseline[side]
            metrics = _metrics_delta(current, baseline)
            rate = int(
                self._device_info.get(side, {}).get(
                    "sample_rate_hz", 100
                )
            )
            board_qc.append(
                BoardQcInput(
                    side=side,
                    configured_rate_hz=rate,
                    duration_s=duration_s,
                    host_metrics=metrics,
                    firmware_health=stop_results[side].health,
                    start_acknowledged=(
                        self._start_result is not None
                        and side in self._start_result.acknowledged
                    ),
                    stop_acknowledged=stop_results[side].acknowledged,
                )
            )
        qc = evaluate_session_qc(
            SessionQcInput(
                boards=tuple(board_qc),
                start_skew_ns=self._start_result.start_skew_ns if self._start_result else None,
                journal_queue_overflow=journal.metrics.queue_overflow_faults,
                journal_samples_written=journal.metrics.samples_written,
                journal_fault_code=(
                    journal.fatal_fault.code if journal.fatal_fault is not None else None
                ),
                journal_fault_message=(
                    journal.fatal_fault.message if journal.fatal_fault is not None else None
                ),
            )
        )
        summary = {
            "quality": qc.level.name,
            "duration_s": duration_s,
            "journal": {
                "samples_written": journal.metrics.samples_written,
                "queue_high_water": journal.metrics.queue_high_water,
                "queue_overflow_faults": journal.metrics.queue_overflow_faults,
                "max_write_latency_ns": journal.metrics.max_write_latency_ns,
                "fatal_fault": (
                    dataclasses.asdict(journal.fatal_fault)
                    if journal.fatal_fault is not None
                    else None
                ),
            },
            "reasons": [
                {
                    "code": reason.code,
                    "level": reason.level.name,
                    "detail": reason.detail,
                    "side": reason.side.value if reason.side else None,
                }
                for reason in qc.reasons
            ],
        }
        final_path = journal.finalize(summary)
        session_id = journal.session_id
        metadata = dict(self._record_metadata or {})
        manifest = {
            **metadata,
            **summary,
            "session_id": session_id,
            "journal_path": str(final_path),
            "sample_counts": {
                item.side.value: item.host_metrics.samples_received for item in board_qc
            },
            "finalized_utc_ms": int(time.time() * 1000),
        }
        self._write_json_atomic(final_path.with_suffix(".summary.json"), manifest)
        self._journal = None
        self._record_sides = ()
        self._record_started_ns = None
        self._start_result = None
        self._record_metadata = None
        self._metric_baseline.clear()
        value = {
            "session_id": session_id,
            "journal_path": str(final_path),
            **summary,
        }
        self._emit("recording_state", {"state": "finalized", **value})
        return value

    async def _cmd_recover(self, payload: dict[str, Any]) -> dict[str, Any]:
        file_name = str(payload["file_name"])
        if Path(file_name).name != file_name or not file_name.endswith(".open"):
            raise ValueError("file_name must be a .open file name inside the journal root")
        source = self.journal_root / file_name
        recovered = recover_open_journal(source)
        return {"source": str(source), "recovered": str(recovered)}

    async def _cmd_list_sessions(self, payload: dict[str, Any]) -> dict[str, Any]:
        del payload
        sessions: list[dict[str, Any]] = []
        for journal_path in sorted(
            self.journal_root.glob("*.waj"), key=lambda path: path.stat().st_mtime, reverse=True
        ):
            manifest_path = journal_path.with_suffix(".summary.json")
            if manifest_path.exists():
                try:
                    value = json.loads(manifest_path.read_text(encoding="utf-8"))
                    if isinstance(value, dict):
                        sessions.append(value)
                        continue
                except (OSError, json.JSONDecodeError):
                    pass
            sessions.append(self._fallback_session_summary(journal_path))
        return {"sessions": sessions}

    async def _cmd_export_session(self, payload: dict[str, Any]) -> dict[str, Any]:
        session_id = str(payload["session_id"])
        source = self._journal_path_for_session(session_id)
        output_raw = payload.get("output_path")
        output = Path(str(output_raw)) if output_raw else source.with_suffix(".csv")
        output.parent.mkdir(parents=True, exist_ok=True)
        exported = JournalReader(source).export_csv(output)
        return {"session_id": session_id, "output_path": str(exported)}

    async def _cmd_diagnostic_report(self, payload: dict[str, Any]) -> dict[str, Any]:
        output_raw = payload.get("output_path")
        stamp = time.strftime("%Y%m%d-%H%M%S")
        output = (
            Path(str(output_raw))
            if output_raw
            else self.journal_root / f"diagnostics-{stamp}.json"
        )
        output.parent.mkdir(parents=True, exist_ok=True)
        ipc_status = payload.get("_ipc_status")
        report = {
            "generated_utc_ms": int(time.time() * 1000),
            "journal_root": str(self.journal_root),
            "status": self.status(),
            "ipc": dict(ipc_status) if isinstance(ipc_status, dict) else {},
        }
        self._write_json_atomic(output, report)
        return {"output_path": str(output)}

    def _journal_path_for_session(self, session_id: str) -> Path:
        if not session_id or any(ch not in "0123456789abcdefABCDEF-" for ch in session_id):
            raise ValueError("invalid session_id")
        path = self.journal_root / f"{session_id}.waj"
        if not path.exists():
            raise FileNotFoundError(path)
        return path

    def _fallback_session_summary(self, path: Path) -> dict[str, Any]:
        records = JournalReader(path).read_all()
        metadata: dict[str, Any] = {}
        final: dict[str, Any] = {}
        sample_counts = {"L": 0, "R": 0}
        for record in records:
            if record.kind is RecordKind.SESSION_META and record.json_value:
                metadata = dict(record.json_value)
            elif record.kind is RecordKind.FINALIZE and record.json_value:
                final = dict(record.json_value)
            elif record.kind is RecordKind.SAMPLE and record.sample is not None:
                sample_counts[record.sample.side.value] += 1
        return {
            **metadata,
            **final,
            "session_id": str(metadata.get("session_id") or final.get("session_id") or path.stem),
            "journal_path": str(path),
            "sample_counts": sample_counts,
            "finalized_utc_ms": int(path.stat().st_mtime * 1000),
        }

    @staticmethod
    def _write_json_atomic(path: Path, value: dict[str, Any]) -> None:
        temp = path.with_name(path.name + ".tmp")
        with temp.open("w", encoding="utf-8") as handle:
            json.dump(value, handle, indent=2, sort_keys=True)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temp, path)

    def status(self) -> dict[str, Any]:
        boards: dict[str, Any] = {}
        now_ns = time.monotonic_ns()
        for side in WheelSide:
            device_id = self.engine.device_id(side)
            metrics = self.engine.metrics(side)
            model = self.lifecycle.clock_model(side)
            previous = self._status_rate_baseline.get(side)
            notifications_hz = None
            samples_hz = None
            if previous is not None and now_ns > previous[0]:
                elapsed_s = (now_ns - previous[0]) / 1_000_000_000
                notifications_hz = (metrics.notifications_received - previous[1]) / elapsed_s
                samples_hz = (metrics.samples_received - previous[2]) / elapsed_s
            self._status_rate_baseline[side] = (
                now_ns,
                metrics.notifications_received,
                metrics.samples_received,
            )
            boards[side.value] = {
                "connected": device_id is not None,
                "device_id": device_id,
                "info": self._device_info.get(side),
                "mtu": self.transport.negotiated_mtu(device_id) if device_id else None,
                "notifications": metrics.notifications_received,
                "samples": metrics.samples_received,
                "sequence_gaps": metrics.sequence_gaps,
                "duplicates": metrics.duplicate_samples,
                "out_of_order": metrics.out_of_order_samples,
                "malformed_packets": metrics.malformed_packets,
                "queue_depth": self.engine.pending_notifications(side),
                "queue_high_water": metrics.queue_high_water,
                "queue_overflow_faults": metrics.queue_overflow_faults,
                "notifications_hz": notifications_hz,
                "samples_hz": samples_hz,
                "fatal_fault": dataclasses.asdict(self.engine.fatal_fault(side))
                if self.engine.fatal_fault(side)
                else None,
                "clock": self._clock_payload(side, model) if model else None,
                "health": dataclasses.asdict(self.lifecycle.health(side))
                if self.lifecycle.health(side)
                else None,
            }
        journal = self._journal
        return {
            "boards": boards,
            "recording": journal is not None,
            "journal_root": str(self.journal_root),
            "session_id": journal.session_id if journal else None,
            "journal": {
                "queue_high_water": journal.metrics.queue_high_water,
                "queue_overflow_faults": journal.metrics.queue_overflow_faults,
                "samples_written": journal.metrics.samples_written,
                "max_write_latency_ns": journal.metrics.max_write_latency_ns,
            }
            if journal
            else None,
            "incomplete_sessions": sorted(path.name for path in self.journal_root.glob("*.open")),
        }

    def _selected_sides(self, payload: dict[str, Any]) -> tuple[WheelSide, ...]:
        if "sides" in payload:
            sides = tuple(_side(item) for item in payload["sides"])
        elif "side" in payload:
            sides = (_side(payload["side"]),)
        else:
            sides = tuple(side for side in WheelSide if self.engine.device_id(side) is not None)
        for side in sides:
            self._require_device(side)
        return sides

    def _require_device(self, side: WheelSide) -> str:
        device_id = self.engine.device_id(side)
        if device_id is None:
            raise RuntimeError(f"{side.value} wheel is not connected")
        return device_id

    @staticmethod
    def _clock_payload(side: WheelSide, model: ClockModel) -> dict[str, Any]:
        return {
            "side": side.value,
            "slope_ns_per_us": model.slope_ns_per_us,
            "intercept_ns": model.intercept_ns,
            "drift_ppm": model.drift_ppm,
            "best_rtt_ns": model.best_rtt_ns,
            "median_rtt_ns": model.median_rtt_ns,
            "residual_rms_ns": model.residual_rms_ns,
            "observation_count": model.observation_count,
        }

    @staticmethod
    def _start_payload(result: StartResult) -> dict[str, Any]:
        return {
            "pc_start_ns": result.pc_start_ns,
            "acknowledged": sorted(side.value for side in result.acknowledged),
            "mapped_start_ns": {side.value: value for side, value in result.mapped_start_ns.items()},
            "target_device_us": {side.value: value for side, value in result.target_device_us.items()},
            "start_skew_ns": result.start_skew_ns,
        }
