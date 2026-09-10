import asyncio
import json
import struct
from pathlib import Path

from tools.pc_acquisition.ipc import AcquisitionIpcServer, PROTOCOL_VERSION, MAX_MESSAGE_BYTES
from tools.pc_acquisition.service import AcquisitionService
from tools.pc_acquisition.transport import FakeBleTransport
from tools.pc_acquisition.uuids import INFO_UUID


def _message(message_type, payload=None, request_id=None, version=PROTOCOL_VERSION):
    value = {
        "protocol_version": version,
        "type": message_type,
        "payload": payload or {},
    }
    if request_id is not None:
        value["request_id"] = request_id
    return (json.dumps(value) + "\n").encode()


async def _read(reader):
    return json.loads((await reader.readline()).decode())


def test_localhost_ipc_handshake_status_connect_and_no_raw_sample_event(tmp_path: Path):
    async def scenario():
        transport = FakeBleTransport()
        # L, fw 1.7.0, ranges, float scales, model 2, replay capability.
        transport.read_values[("left-device", INFO_UUID)] = (
            bytes([0x4C, 1, 7, 0, 1, 3])
            + struct.pack("<ff", 4 / 32768, 2000 / 32768)
            + bytes([2, 1])
        )
        transport.mtu["left-device"] = 247
        service = AcquisitionService(transport, journal_root=tmp_path)
        server = AcquisitionIpcServer(service, port=0)
        await server.start()
        reader, writer = await asyncio.open_connection("127.0.0.1", server.bound_port)

        writer.write(_message("hello", request_id="h1"))
        await writer.drain()
        hello = await _read(reader)
        assert hello["type"] == "hello_ack"
        assert hello["protocol_version"] == PROTOCOL_VERSION

        writer.write(_message("connect", {"device_id": "left-device"}, "c1"))
        await writer.drain()
        # connection_state event is published before command response.
        first = await _read(reader)
        second = await _read(reader)
        messages = {first["type"]: first, second["type"]: second}
        assert messages["connection_state"]["payload"]["side"] == "L"
        assert messages["response"]["request_id"] == "c1"
        assert messages["response"]["payload"]["result"]["mtu"] == 247

        writer.write(_message("status", request_id="s1"))
        await writer.drain()
        status = await _read(reader)
        assert status["payload"]["result"]["boards"]["L"]["connected"]

        # IMU is intentionally not asserted over IPC: raw notification events
        # are owned by the daemon and only the throttled sample_preview channel
        # may cross the process boundary.
        writer.close()
        await writer.wait_closed()
        await server.close()

    asyncio.run(scenario())


def test_ipc_rejects_wrong_version_and_requires_request_id_for_commands(tmp_path: Path):
    async def scenario():
        service = AcquisitionService(FakeBleTransport(), journal_root=tmp_path)
        server = AcquisitionIpcServer(service, port=0)
        await server.start()

        reader, writer = await asyncio.open_connection("127.0.0.1", server.bound_port)
        writer.write(_message("hello", version=999))
        await writer.drain()
        error = await _read(reader)
        assert error["type"] == "error"
        assert error["payload"]["code"] == "protocol_error"
        writer.close()
        await writer.wait_closed()

        reader, writer = await asyncio.open_connection("127.0.0.1", server.bound_port)
        writer.write(_message("hello", request_id="h"))
        await writer.drain()
        await _read(reader)
        writer.write(_message("status"))
        await writer.drain()
        error = await _read(reader)
        assert error["payload"]["code"] == "missing_request_id"
        writer.close()
        await writer.wait_closed()
        await server.close()

    asyncio.run(scenario())


def test_ipc_probe_disconnect_does_not_break_server(tmp_path: Path):
    async def scenario():
        service = AcquisitionService(FakeBleTransport(), journal_root=tmp_path)
        server = AcquisitionIpcServer(service, port=0)
        await server.start()

        # Simulate daemon_reachable probe: connects and immediately closes
        _reader, probe_writer = await asyncio.open_connection("127.0.0.1", server.bound_port)
        probe_writer.close()
        await probe_writer.wait_closed()

        # Server must continue accepting normal connections
        reader, writer = await asyncio.open_connection("127.0.0.1", server.bound_port)
        writer.write(_message("hello", request_id="h-probe"))
        await writer.drain()
        hello = await _read(reader)
        assert hello["type"] == "hello_ack"

        writer.close()
        await writer.wait_closed()
        await server.close()

    asyncio.run(scenario())


def test_ipc_shutdown_acknowledges_before_requesting_process_exit(tmp_path: Path):
    async def scenario():
        service = AcquisitionService(FakeBleTransport(), journal_root=tmp_path)
        server = AcquisitionIpcServer(service, port=0)
        await server.start()
        reader, writer = await asyncio.open_connection("127.0.0.1", server.bound_port)
        writer.write(_message("hello", request_id="hello"))
        await writer.drain()
        await _read(reader)

        writer.write(_message("shutdown", request_id="shutdown"))
        await writer.drain()
        response = await _read(reader)
        assert response["payload"]["result"] == {
            "ready": True,
            "recording_finalized": False,
            "live_stopped": False,
        }
        assert server.shutdown_requested.is_set()

        writer.close()
        await writer.wait_closed()
        await server.close()

    asyncio.run(scenario())


def test_ipc_supports_messages_exceeding_64kb(tmp_path: Path):
    async def scenario():
        service = AcquisitionService(FakeBleTransport(), journal_root=tmp_path)
        # Create 200 dummy sessions with summaries to exceed 64 KB
        for i in range(200):
            session_id = f"test-session-{i:04d}"
            waj_path = tmp_path / f"Topic_{i}" / f"Trial1_{session_id}.waj"
            waj_path.parent.mkdir(parents=True, exist_ok=True)
            waj_path.write_bytes(b"\x00" * 32)
            summary_path = waj_path.with_suffix(".summary.json")
            summary_path.write_text(
                json.dumps({
                    "session_id": session_id,
                    "athlete": f"Athlete-{i}",
                    "topic": f"Topic_{i}",
                    "trial_number": 1,
                    "sample_rate_hz": 200,
                    "duration_s": 12.34,
                    "quality": "GOOD",
                    "sample_counts": {"L": 2400, "R": 2400},
                    "journal_path": str(waj_path),
                    "started_utc_ms": 1700000000000 + i * 1000,
                    "finalized_utc_ms": 1700000012340 + i * 1000,
                }),
                encoding="utf-8",
            )

        server = AcquisitionIpcServer(service, port=0)
        await server.start()

        reader, writer = await asyncio.open_connection(
            "127.0.0.1", server.bound_port, limit=MAX_MESSAGE_BYTES
        )
        writer.write(_message("hello", request_id="h-large"))
        await writer.drain()
        hello = await _read(reader)
        assert hello["type"] == "hello_ack"

        writer.write(_message("list_sessions", request_id="ls-large"))
        await writer.drain()
        raw = await reader.readline()
        assert len(raw) > 64 * 1024  # Confirms payload exceeds old 64 KB limit
        response = json.loads(raw.decode())
        assert response["type"] == "response"
        assert len(response["payload"]["result"]["sessions"]) == 200

        writer.close()
        await writer.wait_closed()
        await server.close()

    asyncio.run(scenario())
