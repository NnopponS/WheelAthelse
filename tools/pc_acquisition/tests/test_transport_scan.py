import asyncio

from tools.pc_acquisition.transport import BleakTransport
from tools.pc_acquisition.uuids import SERVICE_UUID


class _Device:
    def __init__(self, address: str, name: str | None) -> None:
        self.address = address
        self.name = name


class _Advertisement:
    def __init__(
        self,
        *,
        local_name: str | None,
        rssi: int | None,
        service_uuids: list[str] | None = None,
    ) -> None:
        self.local_name = local_name
        self.rssi = rssi
        self.service_uuids = service_uuids or []


class _Scanner:
    @staticmethod
    async def discover(*, timeout: float, return_adv: bool):
        assert timeout == 1.25
        assert return_adv is True
        return {
            "left": (
                _Device("left-id", None),
                _Advertisement(
                    local_name="WheelAthlete-L",
                    rssi=-47,
                    service_uuids=[],
                ),
            ),
            "right": (
                _Device("right-id", "custom-xiao"),
                _Advertisement(
                    local_name=None,
                    rssi=-55,
                    service_uuids=[SERVICE_UUID.upper()],
                ),
            ),
            "other": (
                _Device("other-id", "Unrelated"),
                _Advertisement(local_name="Unrelated", rssi=-30),
            ),
        }


def test_windows_scan_uses_advertisement_rssi_and_service_uuid_filter():
    async def scenario():
        transport = object.__new__(BleakTransport)
        transport._BleakScanner = _Scanner
        devices = await transport.scan(1.25)
        assert [(item.device_id, item.name, item.rssi) for item in devices] == [
            ("left-id", "WheelAthlete-L", -47),
            ("right-id", "custom-xiao", -55),
        ]

    asyncio.run(scenario())
