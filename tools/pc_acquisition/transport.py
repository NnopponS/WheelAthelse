from __future__ import annotations

import time
from collections.abc import Callable
from typing import Protocol

from .models import DeviceCandidate
from .uuids import IMU_DATA_UUID, SERVICE_UUID, SYNC_UUID


NotificationCallback = Callable[[bytes, int], None]


class BleTransport(Protocol):
    async def scan(self, timeout_s: float = 5.0) -> list[DeviceCandidate]: ...

    async def connect(self, device_id: str) -> None: ...

    async def disconnect(self, device_id: str) -> None: ...

    async def subscribe(
        self, device_id: str, characteristic_uuid: str, callback: NotificationCallback
    ) -> None: ...

    async def unsubscribe(self, device_id: str, characteristic_uuid: str) -> None: ...

    async def read(self, device_id: str, characteristic_uuid: str) -> bytes: ...

    async def write(
        self,
        device_id: str,
        characteristic_uuid: str,
        payload: bytes,
        *,
        response: bool = True,
    ) -> None: ...

    def negotiated_mtu(self, device_id: str) -> int | None: ...


class BleakTransport:
    """Production Windows BLE transport backed by Bleak/WinRT.

    Bleak is imported lazily so parser/queue/synchronization tests remain fully
    hardware-independent.  The transport callback records the monotonic arrival
    timestamp before handing the immutable bytes to the acquisition core.
    """

    def __init__(self) -> None:
        try:
            from bleak import BleakClient, BleakScanner
        except ImportError as exc:  # pragma: no cover - environment dependent
            raise RuntimeError(
                "Bleak is required for Windows BLE acquisition. "
                "Install tools/pc_acquisition/requirements.txt."
            ) from exc
        self._BleakClient = BleakClient
        self._BleakScanner = BleakScanner
        self._clients: dict[str, object] = {}
        self._callbacks: dict[tuple[str, str], object] = {}

    async def scan(self, timeout_s: float = 5.0) -> list[DeviceCandidate]:
        devices = await self._BleakScanner.discover(timeout=timeout_s)
        result: list[DeviceCandidate] = []
        for device in devices:
            name = getattr(device, "name", None) or ""
            # Some Windows advertisements do not expose service UUIDs through
            # the simple discover() object, so name filtering is only the first
            # pass; connect/probe remains authoritative.
            if name.startswith("WheelAthlete"):
                result.append(
                    DeviceCandidate(
                        device_id=str(device.address),
                        name=name,
                        rssi=getattr(device, "rssi", None),
                    )
                )
        return result

    async def connect(self, device_id: str) -> None:
        if device_id in self._clients:
            return
        client = self._BleakClient(device_id)
        await client.connect(timeout=10.0)
        self._clients[device_id] = client

    async def disconnect(self, device_id: str) -> None:
        client = self._clients.pop(device_id, None)
        if client is not None:
            await client.disconnect()
        for key in [key for key in self._callbacks if key[0] == device_id]:
            self._callbacks.pop(key, None)

    def _client(self, device_id: str):
        try:
            return self._clients[device_id]
        except KeyError as exc:
            raise RuntimeError(f"BLE device not connected: {device_id}") from exc

    async def subscribe(
        self, device_id: str, characteristic_uuid: str, callback: NotificationCallback
    ) -> None:
        client = self._client(device_id)

        def native_callback(_sender, data: bytearray) -> None:
            callback(bytes(data), time.monotonic_ns())

        self._callbacks[(device_id, characteristic_uuid)] = native_callback
        await client.start_notify(characteristic_uuid, native_callback)

    async def unsubscribe(self, device_id: str, characteristic_uuid: str) -> None:
        client = self._clients.get(device_id)
        if client is None:
            return
        try:
            await client.stop_notify(characteristic_uuid)
        finally:
            self._callbacks.pop((device_id, characteristic_uuid), None)

    async def read(self, device_id: str, characteristic_uuid: str) -> bytes:
        return bytes(await self._client(device_id).read_gatt_char(characteristic_uuid))

    async def write(
        self,
        device_id: str,
        characteristic_uuid: str,
        payload: bytes,
        *,
        response: bool = True,
    ) -> None:
        await self._client(device_id).write_gatt_char(
            characteristic_uuid, payload, response=response
        )

    def negotiated_mtu(self, device_id: str) -> int | None:
        client = self._clients.get(device_id)
        if client is None:
            return None
        value = getattr(client, "mtu_size", None)
        return int(value) if value is not None else None


class FakeBleTransport:
    """Deterministic transport used by automated acquisition tests."""

    def __init__(self) -> None:
        self.connected: set[str] = set()
        self.callbacks: dict[tuple[str, str], NotificationCallback] = {}
        self.read_values: dict[tuple[str, str], bytes] = {}
        self.writes: list[tuple[str, str, bytes, bool]] = []
        self.mtu: dict[str, int] = {}
        self.scan_results: list[DeviceCandidate] = []

    async def scan(self, timeout_s: float = 5.0) -> list[DeviceCandidate]:
        del timeout_s
        return list(self.scan_results)

    async def connect(self, device_id: str) -> None:
        self.connected.add(device_id)

    async def disconnect(self, device_id: str) -> None:
        self.connected.discard(device_id)
        for key in [key for key in self.callbacks if key[0] == device_id]:
            self.callbacks.pop(key, None)

    async def subscribe(
        self, device_id: str, characteristic_uuid: str, callback: NotificationCallback
    ) -> None:
        if device_id not in self.connected:
            raise RuntimeError(f"not connected: {device_id}")
        self.callbacks[(device_id, characteristic_uuid)] = callback

    async def unsubscribe(self, device_id: str, characteristic_uuid: str) -> None:
        self.callbacks.pop((device_id, characteristic_uuid), None)

    async def read(self, device_id: str, characteristic_uuid: str) -> bytes:
        return self.read_values[(device_id, characteristic_uuid)]

    async def write(
        self,
        device_id: str,
        characteristic_uuid: str,
        payload: bytes,
        *,
        response: bool = True,
    ) -> None:
        if device_id not in self.connected:
            raise RuntimeError(f"not connected: {device_id}")
        self.writes.append((device_id, characteristic_uuid, bytes(payload), response))

    def negotiated_mtu(self, device_id: str) -> int | None:
        return self.mtu.get(device_id)

    def emit(
        self,
        device_id: str,
        characteristic_uuid: str,
        payload: bytes,
        *,
        arrival_ns: int | None = None,
    ) -> None:
        callback = self.callbacks[(device_id, characteristic_uuid)]
        callback(bytes(payload), time.monotonic_ns() if arrival_ns is None else arrival_ns)

    def emit_imu(
        self, device_id: str, payload: bytes, *, arrival_ns: int | None = None
    ) -> None:
        self.emit(device_id, IMU_DATA_UUID, payload, arrival_ns=arrival_ns)

    def emit_sync(
        self, device_id: str, payload: bytes, *, arrival_ns: int | None = None
    ) -> None:
        self.emit(device_id, SYNC_UUID, payload, arrival_ns=arrival_ns)
