from __future__ import annotations

import asyncio
import json
from dataclasses import dataclass
from typing import Any

from .service import AcquisitionService


PROTOCOL_VERSION = 1
MAX_MESSAGE_BYTES = 64 * 1024
MAX_PREVIEW_WRITE_BUFFER_BYTES = 256 * 1024


class IpcProtocolError(ValueError):
    pass


def validate_message(value: Any) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise IpcProtocolError("message must be a JSON object")
    if value.get("protocol_version") != PROTOCOL_VERSION:
        raise IpcProtocolError(
            f"unsupported protocol_version {value.get('protocol_version')!r}; expected {PROTOCOL_VERSION}"
        )
    message_type = value.get("type")
    if not isinstance(message_type, str) or not message_type:
        raise IpcProtocolError("message type must be a non-empty string")
    payload = value.get("payload", {})
    if not isinstance(payload, dict):
        raise IpcProtocolError("payload must be an object")
    request_id = value.get("request_id")
    if request_id is not None and (
        not isinstance(request_id, str) or not request_id or len(request_id) > 128
    ):
        raise IpcProtocolError("request_id must be a non-empty string <=128 chars")
    return value


def encode_message(message_type: str, payload: dict[str, Any], *, request_id: str | None = None) -> bytes:
    value: dict[str, Any] = {
        "protocol_version": PROTOCOL_VERSION,
        "type": message_type,
        "payload": payload,
    }
    if request_id is not None:
        value["request_id"] = request_id
    encoded = json.dumps(value, separators=(",", ":"), ensure_ascii=False).encode("utf-8") + b"\n"
    if len(encoded) > MAX_MESSAGE_BYTES:
        raise IpcProtocolError("encoded message exceeds maximum size")
    return encoded


@dataclass(eq=False)
class _Client:
    writer: asyncio.StreamWriter
    ready: bool = False


class AcquisitionIpcServer:
    def __init__(
        self,
        service: AcquisitionService,
        *,
        host: str = "127.0.0.1",
        port: int = 8765,
    ) -> None:
        if host not in ("127.0.0.1", "localhost"):
            raise ValueError("acquisition IPC must bind to localhost only")
        self.service = service
        self.host = "127.0.0.1"
        self.port = port
        self._server: asyncio.AbstractServer | None = None
        self._clients: set[_Client] = set()
        self._loop: asyncio.AbstractEventLoop | None = None
        self._preview_events_sent = 0
        self._preview_events_dropped = 0
        self._max_preview_write_buffer_bytes = 0
        service.set_event_sink(self._publish_from_service)

    @property
    def bound_port(self) -> int:
        if self._server is None or not self._server.sockets:
            return self.port
        return int(self._server.sockets[0].getsockname()[1])

    async def start(self) -> None:
        await self.service.start()
        self._loop = asyncio.get_running_loop()
        self._server = await asyncio.start_server(self._handle_client, self.host, self.port)

    async def close(self) -> None:
        server = self._server
        self._server = None
        if server is not None:
            server.close()
            await server.wait_closed()
        clients = list(self._clients)
        self._clients.clear()
        for client in clients:
            client.writer.close()
            try:
                await client.writer.wait_closed()
            except Exception:
                pass
        await self.service.close()

    def _publish_from_service(self, event_type: str, payload: dict[str, Any]) -> None:
        loop = self._loop
        if loop is None or loop.is_closed():
            return
        loop.call_soon_threadsafe(
            lambda: asyncio.create_task(self.publish(event_type, payload))
        )

    async def publish(self, event_type: str, payload: dict[str, Any]) -> None:
        encoded = encode_message(event_type, payload)
        failed: list[_Client] = []
        is_preview = event_type == "sample_preview"
        for client in tuple(self._clients):
            if not client.ready:
                continue
            try:
                if is_preview:
                    transport = client.writer.transport
                    buffered = int(transport.get_write_buffer_size())
                    self._max_preview_write_buffer_bytes = max(
                        self._max_preview_write_buffer_bytes, buffered
                    )
                    if buffered >= MAX_PREVIEW_WRITE_BUFFER_BYTES:
                        # Preview is explicitly best-effort. A frozen/slow UI
                        # must never create unbounded socket backpressure in the
                        # daemon that owns the lossless raw path.
                        self._preview_events_dropped += 1
                        continue
                    client.writer.write(encoded)
                    self._preview_events_sent += 1
                    # Do not await drain for preview telemetry. The bounded
                    # write-buffer check above makes this non-blocking and
                    # disposable per client.
                    continue
                client.writer.write(encoded)
                await client.writer.drain()
            except Exception:
                failed.append(client)
        for client in failed:
            self._clients.discard(client)
            client.writer.close()

    def ipc_status(self) -> dict[str, int]:
        return {
            "ready_clients": sum(1 for client in self._clients if client.ready),
            "preview_events_sent": self._preview_events_sent,
            "preview_events_dropped": self._preview_events_dropped,
            "max_preview_write_buffer_bytes": self._max_preview_write_buffer_bytes,
            "preview_write_buffer_limit_bytes": MAX_PREVIEW_WRITE_BUFFER_BYTES,
        }

    async def _handle_client(
        self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter
    ) -> None:
        peer = writer.get_extra_info("peername")
        if peer and peer[0] not in ("127.0.0.1", "::1"):
            writer.close()
            return
        client = _Client(writer=writer)
        self._clients.add(client)
        try:
            first = await self._read_message(reader)
            if first["type"] != "hello":
                raise IpcProtocolError("first message must be hello")
            client.ready = True
            writer.write(
                encode_message(
                    "hello_ack",
                    {"server": "WheelAthlete PC Acquisition", "protocol_version": PROTOCOL_VERSION},
                    request_id=first.get("request_id"),
                )
            )
            await writer.drain()
            while True:
                try:
                    message = await self._read_message(reader)
                except EOFError:
                    break
                request_id = message.get("request_id")
                if request_id is None:
                    await self._send_error(writer, None, "missing_request_id", "commands require request_id")
                    continue
                try:
                    command_payload = dict(message.get("payload", {}))
                    if message["type"] == "diagnostic_report":
                        # The service owns the report file, while the IPC server
                        # owns socket/UI-isolation counters. Inject a trusted
                        # internal snapshot so exported diagnostics contain both.
                        command_payload["_ipc_status"] = self.ipc_status()
                    result = await self.service.handle_command(
                        message["type"], command_payload
                    )
                    if message["type"] == "status":
                        result = {**result, "ipc": self.ipc_status()}
                except Exception as exc:
                    await self._send_error(
                        writer, request_id, "command_failed", str(exc)
                    )
                else:
                    writer.write(encode_message("response", {"ok": True, "result": result}, request_id=request_id))
                    await writer.drain()
        except IpcProtocolError as exc:
            await self._send_error(writer, None, "protocol_error", str(exc))
        finally:
            self._clients.discard(client)
            writer.close()
            try:
                await writer.wait_closed()
            except Exception:
                pass

    async def _read_message(self, reader: asyncio.StreamReader) -> dict[str, Any]:
        try:
            raw = await reader.readuntil(b"\n")
        except asyncio.IncompleteReadError as exc:
            if not exc.partial:
                raise EOFError from exc
            raise IpcProtocolError("connection ended inside a JSON message") from exc
        except asyncio.LimitOverrunError as exc:
            raise IpcProtocolError("message exceeds stream limit") from exc
        if len(raw) > MAX_MESSAGE_BYTES:
            raise IpcProtocolError("message exceeds maximum size")
        try:
            value = json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise IpcProtocolError("invalid UTF-8 JSON message") from exc
        return validate_message(value)

    @staticmethod
    async def _send_error(
        writer: asyncio.StreamWriter,
        request_id: str | None,
        code: str,
        message: str,
    ) -> None:
        try:
            writer.write(
                encode_message(
                    "error",
                    {"ok": False, "code": code, "message": message},
                    request_id=request_id,
                )
            )
            await writer.drain()
        except Exception:
            pass
