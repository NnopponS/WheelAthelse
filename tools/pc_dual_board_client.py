#!/usr/bin/env python3
"""WheelAthlete PC Dual Board BLE Client & Diagnoser.

Connects to 2 WheelAthlete BLE boards (Left & Right) directly from a PC (Windows/Mac/Linux)
using Python `bleak`. Captures IMU streams, tests dual-board connection stability, monitors
packet drops and transport health, and saves recorded sessions to CSV.

Usage:
    python tools/pc_dual_board_client.py [duration_seconds]

Requirements:
    pip install bleak
"""

import asyncio
import csv
import struct
import sys
import time
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Tuple

# Set stdout encoding to UTF-8 on Windows
if sys.platform == "win32":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

try:
    from bleak import BleakScanner, BleakClient
except ImportError:
    print("Error: 'bleak' is required. Install via: pip install bleak", file=sys.stderr)
    sys.exit(1)


# ── UUID Constants ────────────────────────────────────────────────────────────

SERVICE_UUID = "0000a1b2-0000-1000-8000-00805f9b34fb"
IMU_DATA_UUID = "0000a1b3-0000-1000-8000-00805f9b34fb"
CONTROL_UUID = "0000a1b4-0000-1000-8000-00805f9b34fb"
SYNC_UUID = "0000a1b5-0000-1000-8000-00805f9b34fb"
INFO_UUID = "0000a1b6-0000-1000-8000-00805f9b34fb"
CONFIG_UUID = "0000a1b7-0000-1000-8000-00805f9b34fb"
BATTERY_LEVEL_UUID = "00002a19-0000-1000-8000-00805f9b34fb"


# ── Data Classes ──────────────────────────────────────────────────────────────

@dataclass
class BoardStats:
    wheel_side: str  # 'L' or 'R'
    device_name: str
    address: str
    accel_scale: float = 1 / 16384.0  # default ±2g
    gyro_scale: float = 1 / 16.4      # default ±2000dps
    sample_count: int = 0
    packet_count: int = 0
    seq_gaps: int = 0
    drop_count: int = 0
    transport_failures: int = 0
    last_seq: Optional[int] = None
    battery_pct: Optional[int] = None
    samples: List[Tuple] = field(default_factory=list)
    start_time_ms: float = 0.0
    last_sample_time: float = 0.0
    hz: float = 0.0


# ── Parser Helpers ────────────────────────────────────────────────────────────

def parse_info(data: bytes) -> Tuple[str, float, float]:
    """Parse 16-byte Info characteristic.
    Layout: [wheel_id][fw_maj][fw_min][fw_pat][accel_range][gyro_range][accel_scale float32][gyro_scale float32]...
    """
    if len(data) < 16:
        raise ValueError(f"Invalid Info length: {len(data)}")
    wheel_char = chr(data[0]) if data[0] in (0x4C, 0x52) else '?'
    accel_scale, gyro_scale = struct.unpack_from("<ff", data, 6)
    return wheel_char, accel_scale, gyro_scale


def parse_imu_batch(data: bytes, stats: BoardStats) -> List[Tuple]:
    """Parse IMU notification packet.
    Layout: [uint8 count][sample_0][sample_1]...[sample_N-1]
    Sample layout (20 bytes): [uint32 seq][uint32 t_device_us][int16 ax,ay,az,gx,gy,gz]
    """
    if not data:
        return []
    count = data[0]
    expected_len = 1 + count * 20
    if len(data) < expected_len:
        print(f"[{stats.wheel_side}] Warning: Truncated batch packet! Got {len(data)}, expected {expected_len}")
        return []

    parsed = []
    now_ms = time.time() * 1000.0
    for i in range(count):
        offset = 1 + i * 20
        seq, t_device_us, ax_raw, ay_raw, az_raw, gx_raw, gy_raw, gz_raw = struct.unpack_from("<IIhhhhhh", data, offset)

        # Track seq gaps
        if stats.last_seq is not None:
            expected_seq = (stats.last_seq + 1) & 0xFFFFFFFF
            if seq != expected_seq:
                gap = (seq - expected_seq) & 0xFFFFFFFF
                stats.seq_gaps += gap
        stats.last_seq = seq

        ax = ax_raw * stats.accel_scale
        ay = ay_raw * stats.accel_scale
        az = az_raw * stats.accel_scale
        gx = gx_raw * stats.gyro_scale
        gy = gy_raw * stats.gyro_scale
        gz = gz_raw * stats.gyro_scale

        row = (seq, stats.wheel_side, int(now_ms), t_device_us, round(now_ms, 3), ax, ay, az, gx, gy, gz, 0)
        parsed.append(row)

    stats.sample_count += count
    stats.packet_count += 1
    stats.last_sample_time = time.time()
    return parsed


def parse_sync_event(data: bytes, stats: BoardStats):
    """Parse Sync characteristic notification event."""
    if not data:
        return
    event_id = data[0]
    if event_id == 0x10 and len(data) >= 5:  # DROP_COUNT
        new_drops = struct.unpack_from("<I", data, 1)[0]
        stats.drop_count += new_drops
        print(f"\n[DROP] [{stats.wheel_side}] DROP_COUNT Event! +{new_drops} drops (Total drops: {stats.drop_count})")
    elif event_id == 0x60 and len(data) >= 20:  # ACQ_HEALTH (protocol 1.6)
        state_code, produced, notified, queue_drops, failures, q_depth = struct.unpack_from("<BIIIIH", data, 1)
        stats.drop_count = queue_drops
        stats.transport_failures = failures
        if failures > 0 or queue_drops > 0 or q_depth > 50:
            print(f"\n[HEALTH] [{stats.wheel_side}] ACQ_HEALTH: state={state_code}, produced={produced}, notified={notified}, queue_drops={queue_drops}, failures={failures}, queue_depth={q_depth}")


# ── Dual Board BLE Manager ────────────────────────────────────────────────────

class PcDualBoardClient:
    def __init__(self, duration_s: int = 30, output_csv: Optional[str] = None):
        self.duration_s = duration_s
        self.output_csv = output_csv
        self.boards: Dict[str, BoardStats] = {}
        self.clients: Dict[str, BleakClient] = {}
        self.all_samples: List[Tuple] = []

    async def scan(self) -> Tuple[Optional[str], Optional[str]]:
        """Scan for WheelAthlete Left and Right devices."""
        print("[SCAN] Scanning for WheelAthlete BLE boards (Left & Right)...")
        devices = await BleakScanner.discover(timeout=5.0)

        left_addr = None
        right_addr = None

        for d in devices:
            name = d.name or ""
            if "WheelAthlete" in name or name.startswith("M5") or name.startswith("Xiao"):
                print(f"   Found device: '{name}' ({d.address})")
                if name.endswith("-L") or "WheelAthlete-L" in name or "-M5-L" in name:
                    left_addr = d.address
                elif name.endswith("-R") or "WheelAthlete-R" in name or "-M5-R" in name:
                    right_addr = d.address

        if not left_addr or not right_addr:
            print("   Auto-detecting WheelAthlete services for unlabelled devices...")
            for d in devices:
                if left_addr and right_addr:
                    break
                if d.address in (left_addr, right_addr):
                    continue
                try:
                    async with BleakClient(d.address, timeout=3.0) as client:
                        for s in client.services:
                            if s.uuid.lower() == SERVICE_UUID.lower():
                                info_bytes = await client.read_gatt_char(INFO_UUID)
                                wheel_char, _, _ = parse_info(info_bytes)
                                print(f"   Detected {wheel_char} board at {d.address}")
                                if wheel_char == 'L' and not left_addr:
                                    left_addr = d.address
                                elif wheel_char == 'R' and not right_addr:
                                    right_addr = d.address
                except Exception:
                    pass

        return left_addr, right_addr

    async def connect_and_stream_board(self, address: str, target_side: str):
        """Connect to one board, subscribe to characteristics, and handle callbacks."""
        print(f"[CONNECT] Connecting to {target_side} board ({address})...")
        client = BleakClient(address)
        await client.connect(timeout=10.0)

        info_bytes = await client.read_gatt_char(INFO_UUID)
        wheel_side, accel_scale, gyro_scale = parse_info(info_bytes)
        print(f"[OK] [{wheel_side}] Connected! Accel scale={accel_scale}, Gyro scale={gyro_scale}")

        stats = BoardStats(
            wheel_side=wheel_side,
            device_name=f"WheelAthlete-{wheel_side}",
            address=address,
            accel_scale=accel_scale,
            gyro_scale=gyro_scale,
            start_time_ms=time.time() * 1000.0,
        )
        self.boards[wheel_side] = stats
        self.clients[wheel_side] = client

        def imu_callback(sender, data: bytearray):
            samples = parse_imu_batch(bytes(data), stats)
            self.all_samples.extend(samples)

        def sync_callback(sender, data: bytearray):
            parse_sync_event(bytes(data), stats)

        def battery_callback(sender, data: bytearray):
            if data:
                stats.battery_pct = data[0]

        await client.start_notify(IMU_DATA_UUID, imu_callback)
        await client.start_notify(SYNC_UUID, sync_callback)
        try:
            await client.start_notify(BATTERY_LEVEL_UUID, battery_callback)
        except Exception:
            pass

        print(f"[STREAM] [{wheel_side}] Subscribed to IMU Data & Sync streams")

    async def start_all(self):
        """Send START command (cmd=0x01, target_start_us=0 for immediate start) to all connected boards."""
        start_cmd = struct.pack("<BI", 0x01, 0)
        for side, client in self.clients.items():
            print(f"[START] Sending START to [{side}] board...")
            await client.write_gatt_char(CONTROL_UUID, start_cmd, response=True)

    async def stop_all(self):
        """Send STOP command (cmd=0x02) to all connected boards."""
        stop_cmd = struct.pack("<B", 0x02)
        for side, client in self.clients.items():
            print(f"[STOP] Sending STOP to [{side}] board...")
            try:
                await client.write_gatt_char(CONTROL_UUID, stop_cmd, response=True)
                await client.stop_notify(IMU_DATA_UUID)
                await client.stop_notify(SYNC_UUID)
                await client.disconnect()
            except Exception:
                pass

    async def monitor_loop(self):
        """Live dashboard monitor printed every 1 second."""
        start_t = time.time()
        print("\n" + "=" * 75)
        print("LIVE DUAL-BOARD STREAMING STARTED")
        print("=" * 75)

        prev_counts = {side: 0 for side in self.boards}
        prev_time = start_t

        while time.time() - start_t < self.duration_s:
            await asyncio.sleep(1.0)
            now = time.time()
            dt = now - prev_time
            prev_time = now

            status_line = f"Time: {int(now - start_t):2d}s / {self.duration_s}s | "
            for side in sorted(self.boards.keys()):
                st = self.boards[side]
                d_samples = st.sample_count - prev_counts[side]
                prev_counts[side] = st.sample_count
                st.hz = d_samples / dt if dt > 0 else 0.0

                bat = f"{st.battery_pct}%" if st.battery_pct is not None else "?%"
                status_line += (
                    f"[{side}] {st.hz:5.1f} Hz | Total: {st.sample_count:5d} | "
                    f"Gaps: {st.seq_gaps:2d} | Drops: {st.drop_count:2d} | Failures: {st.transport_failures:2d} | Bat: {bat}  "
                )
            print(status_line)

    def save_csv(self):
        """Save collected dual-board samples to CSV file matching check_session.py schema."""
        if not self.all_samples:
            print("[WARN] No samples collected!")
            return

        out_path = Path(self.output_csv) if self.output_csv else Path("tools/test_data") / f"pc_dual_session_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv"
        out_path.parent.mkdir(parents=True, exist_ok=True)

        header = [
            "seq", "wheel", "timestamp_app_ms", "timestamp_device_us",
            "timestamp_synced_ms", "ax", "ay", "az", "gx", "gy", "gz", "marker"
        ]

        sorted_samples = sorted(self.all_samples, key=lambda s: s[4])

        with open(out_path, "w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow(header)
            for row in sorted_samples:
                writer.writerow(row)

        print(f"\n[SAVE] Saved {len(sorted_samples)} samples to: {out_path.resolve()}")


# ── Main Entry Point ──────────────────────────────────────────────────────────

async def main():
    duration_s = 30
    if len(sys.argv) > 1:
        try:
            duration_s = int(sys.argv[1])
        except ValueError:
            pass

    client = PcDualBoardClient(duration_s=duration_s)

    left_addr, right_addr = await client.scan()
    if not left_addr or not right_addr:
        print("\n[ERROR] Could not automatically find both Left and Right boards.")
        print("   Found Left :", left_addr if left_addr else "None")
        print("   Found Right:", right_addr if right_addr else "None")
        print("\nPlease ensure both M5Stick / Xiao boards are powered on and advertising.")
        return

    print(f"\n[TARGETS] Identified:")
    print(f"   Left  Board: {left_addr}")
    print(f"   Right Board: {right_addr}")

    try:
        await asyncio.gather(
            client.connect_and_stream_board(left_addr, "L"),
            client.connect_and_stream_board(right_addr, "R"),
        )
    except Exception as e:
        print(f"\n[ERROR] Connection failed: {e}")
        return

    await client.start_all()

    try:
        await client.monitor_loop()
    except KeyboardInterrupt:
        print("\n[STOP] Interrupted by user.")
    finally:
        await client.stop_all()
        client.save_csv()
        print("\n[DONE] PC Dual Board Test Complete!")


if __name__ == "__main__":
    asyncio.run(main())
