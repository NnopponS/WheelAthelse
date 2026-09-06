from __future__ import annotations

import argparse
import asyncio
from pathlib import Path

from .ipc import AcquisitionIpcServer
from .service import AcquisitionService
from .transport import BleakTransport


async def _run(args: argparse.Namespace) -> None:
    transport = BleakTransport()
    service = AcquisitionService(transport, journal_root=Path(args.journal_root))
    server = AcquisitionIpcServer(service, host="127.0.0.1", port=args.port)
    await server.start()
    print(
        f"WheelAthlete PC acquisition listening on 127.0.0.1:{server.bound_port}",
        flush=True,
    )
    try:
        await asyncio.Event().wait()
    finally:
        await server.close()


def main() -> None:
    parser = argparse.ArgumentParser(description="WheelAthlete Windows acquisition daemon")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument(
        "--journal-root",
        default=str(Path.home() / "Documents" / "WheelAthlete" / "PC Sessions"),
    )
    args = parser.parse_args()
    try:
        asyncio.run(_run(args))
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
