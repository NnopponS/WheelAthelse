from PySide6.QtCore import QCoreApplication

from tools.pc_acquisition.ipc import PROTOCOL_VERSION
from tools.pc_gui.ipc_client import DaemonClient, _Pending


_APP = QCoreApplication.instance() or QCoreApplication([])


def _message(message_type: str, payload: dict, request_id: str | None = None) -> dict:
    value = {
        "protocol_version": PROTOCOL_VERSION,
        "type": message_type,
        "payload": payload,
    }
    if request_id is not None:
        value["request_id"] = request_id
    return value


def test_hello_ack_marks_client_ready():
    client = DaemonClient(auto_reconnect=False)
    ready: list[bool] = []
    client.ready_changed.connect(ready.append)
    client._pending["hello-1"] = _Pending("hello", None, None)
    client._handle_message(
        _message(
            "hello_ack",
            {"server": "WheelAthlete PC Acquisition", "protocol_version": PROTOCOL_VERSION},
            "hello-1",
        )
    )
    assert client.ready
    assert ready == [True]


def test_async_preview_event_is_emitted_without_becoming_a_command_response():
    client = DaemonClient(auto_reconnect=False)
    received: list[tuple[str, dict]] = []
    client.event_received.connect(lambda kind, payload: received.append((kind, payload)))
    client._handle_message(_message("sample_preview", {"side": "L", "seq": 7}))
    assert received == [("sample_preview", {"side": "L", "seq": 7})]


def test_response_correlates_request_and_invokes_callback():
    client = DaemonClient(auto_reconnect=False)
    results: list[dict] = []
    client._pending["req-1"] = _Pending("status", results.append, None)
    client._handle_message(
        _message("response", {"ok": True, "result": {"recording": False}}, "req-1")
    )
    assert results == [{"recording": False}]
    assert "req-1" not in client._pending


def test_protocol_mismatch_is_rejected():
    client = DaemonClient(auto_reconnect=False)
    bad = _message("sample_preview", {})
    bad["protocol_version"] = PROTOCOL_VERSION + 1
    try:
        client._handle_message(bad)
    except ValueError as exc:
        assert "protocol mismatch" in str(exc)
    else:
        raise AssertionError("protocol mismatch was accepted")
