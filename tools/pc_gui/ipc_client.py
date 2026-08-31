from __future__ import annotations

import json
import uuid
from collections.abc import Callable
from dataclasses import dataclass
from typing import Any

from PySide6.QtCore import QObject, QTimer, Signal
from PySide6.QtNetwork import QAbstractSocket, QHostAddress, QTcpSocket

from tools.pc_acquisition.ipc import MAX_MESSAGE_BYTES, PROTOCOL_VERSION


SuccessCallback = Callable[[dict[str, Any]], None]
ErrorCallback = Callable[[str], None]


@dataclass(slots=True)
class _Pending:
    command: str
    on_success: SuccessCallback | None
    on_error: ErrorCallback | None


class DaemonClient(QObject):
    """Qt-native NDJSON client for the isolated acquisition daemon.

    The socket is event-driven inside the GUI thread; it never performs a
    blocking read/write.  BLE, parsing, sequence validation and raw journaling
    remain in the separate acquisition process.
    """

    connection_changed = Signal(bool, str)
    ready_changed = Signal(bool)
    event_received = Signal(str, dict)
    command_succeeded = Signal(str, dict)
    command_failed = Signal(str, str)
    protocol_error = Signal(str)

    def __init__(
        self,
        *,
        host: str = "127.0.0.1",
        port: int = 8765,
        auto_reconnect: bool = True,
        parent: QObject | None = None,
    ) -> None:
        super().__init__(parent)
        self.host = host
        self.port = port
        self.auto_reconnect = auto_reconnect
        self.socket = QTcpSocket(self)
        self.socket.connected.connect(self._on_connected)
        self.socket.disconnected.connect(self._on_disconnected)
        self.socket.readyRead.connect(self._on_ready_read)
        self.socket.errorOccurred.connect(self._on_socket_error)
        self._buffer = bytearray()
        self._pending: dict[str, _Pending] = {}
        self._ready = False
        self._closing = False
        self._reconnect = QTimer(self)
        self._reconnect.setSingleShot(True)
        self._reconnect.setInterval(1500)
        self._reconnect.timeout.connect(self.connect_to_daemon)

    @property
    def ready(self) -> bool:
        return self._ready

    @property
    def connected(self) -> bool:
        return self.socket.state() == QAbstractSocket.SocketState.ConnectedState

    def connect_to_daemon(self) -> None:
        if self._closing or self.connected:
            return
        if self.socket.state() not in {
            QAbstractSocket.SocketState.UnconnectedState,
            QAbstractSocket.SocketState.ClosingState,
        }:
            self.socket.abort()
        self.socket.connectToHost(QHostAddress(self.host), self.port)

    def close(self) -> None:
        self._closing = True
        self._reconnect.stop()
        self._set_ready(False)
        self.socket.disconnectFromHost()
        if self.socket.state() != QAbstractSocket.SocketState.UnconnectedState:
            self.socket.abort()
        self._fail_all("GUI disconnected from acquisition daemon")

    def send_command(
        self,
        command: str,
        payload: dict[str, Any] | None = None,
        *,
        on_success: SuccessCallback | None = None,
        on_error: ErrorCallback | None = None,
    ) -> str:
        if not self._ready:
            raise RuntimeError("acquisition daemon is not ready")
        request_id = uuid.uuid4().hex
        self._pending[request_id] = _Pending(command, on_success, on_error)
        self._write_message(command, payload or {}, request_id=request_id)
        return request_id

    def _on_connected(self) -> None:
        self._buffer.clear()
        self.connection_changed.emit(True, "Connected to acquisition daemon")
        request_id = uuid.uuid4().hex
        self._pending[request_id] = _Pending("hello", None, None)
        self._write_message("hello", {"client": "WheelAthlete Python Research Edition"}, request_id=request_id)

    def _on_disconnected(self) -> None:
        self._set_ready(False)
        self.connection_changed.emit(False, "Acquisition daemon offline")
        self._fail_all("acquisition daemon disconnected")
        if self.auto_reconnect and not self._closing:
            self._reconnect.start()

    def _on_socket_error(self, _error: QAbstractSocket.SocketError) -> None:
        if self.socket.state() == QAbstractSocket.SocketState.UnconnectedState:
            self.connection_changed.emit(False, self.socket.errorString())

    def _on_ready_read(self) -> None:
        self._buffer.extend(bytes(self.socket.readAll()))
        if len(self._buffer) > MAX_MESSAGE_BYTES * 4 and b"\n" not in self._buffer:
            self._fatal_protocol("daemon sent an unterminated oversized message")
            return
        while True:
            newline = self._buffer.find(b"\n")
            if newline < 0:
                break
            raw = bytes(self._buffer[:newline])
            del self._buffer[: newline + 1]
            if not raw:
                continue
            if len(raw) + 1 > MAX_MESSAGE_BYTES:
                self._fatal_protocol("daemon message exceeds maximum size")
                return
            try:
                value = json.loads(raw.decode("utf-8"))
            except (UnicodeDecodeError, json.JSONDecodeError) as exc:
                self._fatal_protocol(f"invalid daemon JSON: {exc}")
                return
            try:
                self._handle_message(value)
            except (KeyError, TypeError, ValueError) as exc:
                self._fatal_protocol(f"invalid daemon message: {exc}")
                return

    def _handle_message(self, value: Any) -> None:
        if not isinstance(value, dict):
            raise ValueError("message is not an object")
        if value.get("protocol_version") != PROTOCOL_VERSION:
            raise ValueError(
                f"protocol mismatch: got {value.get('protocol_version')!r}, expected {PROTOCOL_VERSION}"
            )
        message_type = value.get("type")
        payload = value.get("payload", {})
        request_id = value.get("request_id")
        if not isinstance(message_type, str) or not isinstance(payload, dict):
            raise ValueError("message type/payload invalid")

        if message_type == "hello_ack":
            if isinstance(request_id, str):
                self._pending.pop(request_id, None)
            self._set_ready(True)
            self.connection_changed.emit(True, str(payload.get("server", "Acquisition daemon ready")))
            return

        if message_type == "response":
            if not isinstance(request_id, str):
                raise ValueError("response missing request_id")
            pending = self._pending.pop(request_id, None)
            if pending is None:
                return
            result = payload.get("result", {})
            if not isinstance(result, dict):
                raise ValueError("response result is not an object")
            if pending.on_success is not None:
                pending.on_success(result)
            self.command_succeeded.emit(pending.command, result)
            return

        if message_type == "error":
            message = str(payload.get("message", "unknown daemon error"))
            pending = self._pending.pop(request_id, None) if isinstance(request_id, str) else None
            command = pending.command if pending is not None else "protocol"
            if pending is not None and pending.on_error is not None:
                pending.on_error(message)
            self.command_failed.emit(command, message)
            return

        # Everything else is an asynchronous service event (sample_preview,
        # connection_state, recording_state, sync_status, error, ...).
        self.event_received.emit(message_type, payload)

    def _write_message(
        self,
        message_type: str,
        payload: dict[str, Any],
        *,
        request_id: str,
    ) -> None:
        value = {
            "protocol_version": PROTOCOL_VERSION,
            "type": message_type,
            "payload": payload,
            "request_id": request_id,
        }
        encoded = (
            json.dumps(value, separators=(",", ":"), ensure_ascii=False).encode("utf-8") + b"\n"
        )
        if len(encoded) > MAX_MESSAGE_BYTES:
            self._pending.pop(request_id, None)
            raise ValueError("IPC command exceeds maximum message size")
        self.socket.write(encoded)

    def _set_ready(self, value: bool) -> None:
        if self._ready == value:
            return
        self._ready = value
        self.ready_changed.emit(value)

    def _fail_all(self, message: str) -> None:
        pending = list(self._pending.values())
        self._pending.clear()
        for item in pending:
            if item.on_error is not None:
                item.on_error(message)
            if item.command != "hello":
                self.command_failed.emit(item.command, message)

    def _fatal_protocol(self, message: str) -> None:
        self.protocol_error.emit(message)
        self.socket.abort()
