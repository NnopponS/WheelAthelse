import asyncio
import json
from pathlib import Path

from tools.pc_acquisition.ipc import (
    MAX_PREVIEW_WRITE_BUFFER_BYTES,
    AcquisitionIpcServer,
    _Client,
    encode_message,
)
from tools.pc_acquisition.service import AcquisitionService
from tools.pc_acquisition.transport import FakeBleTransport


class _BufferTransport:
    def __init__(self, size: int = 0) -> None:
        self.size = size

    def get_write_buffer_size(self) -> int:
        return self.size


class _FakeWriter:
    def __init__(self, buffer_size: int = 0) -> None:
        self.transport = _BufferTransport(buffer_size)
        self.writes: list[bytes] = []
        self.drain_calls = 0
        self.closed = False

    def write(self, payload: bytes) -> None:
        self.writes.append(bytes(payload))

    async def drain(self) -> None:
        self.drain_calls += 1

    def close(self) -> None:
        self.closed = True

    async def wait_closed(self) -> None:
        return None


def test_slow_ui_drops_only_preview_without_blocking_critical_events(tmp_path: Path):
    async def scenario():
        service = AcquisitionService(FakeBleTransport(), journal_root=tmp_path)
        server = AcquisitionIpcServer(service, port=0)
        writer = _FakeWriter(MAX_PREVIEW_WRITE_BUFFER_BYTES)
        client = _Client(writer=writer, ready=True)  # type: ignore[arg-type]
        server._clients.add(client)

        await server.publish("sample_preview", {"side": "L", "seq": 1})
        assert writer.writes == []
        assert writer.drain_calls == 0
        assert server.ipc_status()["preview_events_dropped"] == 1

        writer.transport.size = 0
        await server.publish("sample_preview", {"side": "L", "seq": 2})
        assert len(writer.writes) == 1
        # Preview is explicitly best-effort and never waits on socket drain.
        assert writer.drain_calls == 0
        assert server.ipc_status()["preview_events_sent"] == 1

        await server.publish("recording_state", {"state": "stopped"})
        assert len(writer.writes) == 2
        # Critical lifecycle events keep reliable drain semantics.
        assert writer.drain_calls == 1

        status = server.ipc_status()
        assert status["ready_clients"] == 1
        assert status["preview_write_buffer_limit_bytes"] == MAX_PREVIEW_WRITE_BUFFER_BYTES
        assert status["max_preview_write_buffer_bytes"] >= MAX_PREVIEW_WRITE_BUFFER_BYTES

        server._clients.clear()
        await service.close()

    asyncio.run(scenario())


def test_exported_diagnostic_report_contains_ipc_isolation_counters(tmp_path: Path):
    async def scenario():
        service = AcquisitionService(FakeBleTransport(), journal_root=tmp_path)
        server = AcquisitionIpcServer(service, port=0)
        await server.start()
        reader, writer = await asyncio.open_connection("127.0.0.1", server.bound_port)

        writer.write(encode_message("hello", {}, request_id="hello"))
        await writer.drain()
        hello = json.loads((await reader.readline()).decode())
        assert hello["type"] == "hello_ack"

        output = tmp_path / "diagnostic.json"
        writer.write(
            encode_message(
                "diagnostic_report",
                {"output_path": str(output)},
                request_id="diagnostic",
            )
        )
        await writer.drain()
        response = json.loads((await reader.readline()).decode())
        assert response["type"] == "response"
        assert response["request_id"] == "diagnostic"

        report = json.loads(output.read_text(encoding="utf-8"))
        assert report["ipc"]["ready_clients"] == 1
        assert report["ipc"]["preview_write_buffer_limit_bytes"] == (
            MAX_PREVIEW_WRITE_BUFFER_BYTES
        )
        assert "status" in report

        writer.close()
        await writer.wait_closed()
        await server.close()

    asyncio.run(scenario())
