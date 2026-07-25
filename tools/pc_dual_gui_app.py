#!/usr/bin/env python3
"""WheelAthlete PC Dual Board Real-time GUI Graph App.

Features:
  - Real-time dual-wheel IMU graphs (Accelerometer & Gyroscope for L & R wheels)
  - Connects to 2 M5Stick / Xiao BLE boards simultaneously using `bleak`
  - Runs BLE asynchronous handling on a background thread
  - Live statistics display (Hz, total samples, drop counts, transport failures)
  - Built-in CSV recorder and visualizer

Usage:
    python tools/pc_dual_gui_app.py
"""

import asyncio
import csv
import struct
import sys
import threading
import time
from collections import deque
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Tuple

# Fix Windows console encoding
if sys.platform == "win32":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

import tkinter as tk
from tkinter import ttk, messagebox

import matplotlib
matplotlib.use("TkAgg")
from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg
import matplotlib.pyplot as plt


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
BATTERY_LEVEL_UUID = "00002a19-0000-1000-8000-00805f9b34fb"

MAX_BUFFER_POINTS = 500  # 5 seconds at 100 Hz


# ── Data Structures ───────────────────────────────────────────────────────────

@dataclass
class BoardData:
    wheel_side: str  # 'L' or 'R'
    address: str
    accel_scale: float = 1 / 16384.0
    gyro_scale: float = 1 / 16.4
    sample_count: int = 0
    packet_count: int = 0
    seq_gaps: int = 0
    drop_count: int = 0
    transport_failures: int = 0
    last_seq: Optional[int] = None
    battery_pct: Optional[int] = None
    last_hz: float = 0.0

    # Live plotting buffers
    t_buf: deque = field(default_factory=lambda: deque(maxlen=MAX_BUFFER_POINTS))
    az_buf: deque = field(default_factory=lambda: deque(maxlen=MAX_BUFFER_POINTS))
    gz_buf: deque = field(default_factory=lambda: deque(maxlen=MAX_BUFFER_POINTS))

    samples_all: List[Tuple] = field(default_factory=list)


# ── BLE Backend Thread ────────────────────────────────────────────────────────

class BleBackendThread(threading.Thread):
    def __init__(self):
        super().__init__(daemon=True)
        self.loop = asyncio.new_event_loop()
        self.boards: Dict[str, BoardData] = {}
        self.clients: Dict[str, BleakClient] = {}
        self.is_connected = False
        self.is_streaming = False
        self.status_msg = "Idle"
        self.lock = threading.Lock()

    def run(self):
        asyncio.set_event_loop(self.loop)
        self.loop.run_forever()

    def async_run(self, coro):
        return asyncio.run_coroutine_threadsafe(coro, self.loop)

    async def scan_and_connect(self) -> str:
        self.status_msg = "Scanning for WheelAthlete boards..."
        devices = await BleakScanner.discover(timeout=4.0)

        left_addr = None
        right_addr = None

        for d in devices:
            name = d.name or ""
            if "WheelAthlete" in name or name.startswith("M5") or name.startswith("Xiao"):
                if name.endswith("-L") or "WheelAthlete-L" in name or "-M5-L" in name:
                    left_addr = d.address
                elif name.endswith("-R") or "WheelAthlete-R" in name or "-M5-R" in name:
                    right_addr = d.address

        if not left_addr or not right_addr:
            for d in devices:
                if left_addr and right_addr:
                    break
                if d.address in (left_addr, right_addr):
                    continue
                try:
                    async with BleakClient(d.address, timeout=2.5) as client:
                        for s in client.services:
                            if s.uuid.lower() == SERVICE_UUID.lower():
                                info_bytes = await client.read_gatt_char(INFO_UUID)
                                wheel_char = chr(info_bytes[0]) if info_bytes[0] in (0x4C, 0x52) else '?'
                                if wheel_char == 'L' and not left_addr:
                                    left_addr = d.address
                                elif wheel_char == 'R' and not right_addr:
                                    right_addr = d.address
                except Exception:
                    pass

        if not left_addr and not right_addr:
            return "Failed: No WheelAthlete boards found."

        self.status_msg = f"Connecting... L:{left_addr or 'None'}, R:{right_addr or 'None'}"

        async def connect_one(addr: str, side: str):
            if not addr:
                return
            client = BleakClient(addr)
            await client.connect(timeout=8.0)
            info = await client.read_gatt_char(INFO_UUID)
            wheel_side = chr(info[0]) if info[0] in (0x4C, 0x52) else side
            accel_s, gyro_s = struct.unpack_from("<ff", info, 6)

            with self.lock:
                bdata = BoardData(wheel_side=wheel_side, address=addr, accel_scale=accel_s, gyro_scale=gyro_s)
                self.boards[wheel_side] = bdata
                self.clients[wheel_side] = client

            def imu_cb(sender, data: bytearray):
                if not data:
                    return
                cnt = data[0]
                now_s = time.time()
                now_ms = now_s * 1000.0
                for i in range(cnt):
                    off = 1 + i * 20
                    if off + 20 > len(data):
                        break
                    seq, t_us, ax_r, ay_r, az_r, gx_r, gy_r, gz_r = struct.unpack_from("<IIhhhhhh", data, off)

                    with self.lock:
                        if bdata.last_seq is not None:
                            exp = (bdata.last_seq + 1) & 0xFFFFFFFF
                            if seq != exp:
                                bdata.seq_gaps += (seq - exp) & 0xFFFFFFFF
                        bdata.last_seq = seq

                        ax = ax_r * bdata.accel_scale
                        ay = ay_r * bdata.accel_scale
                        az = az_r * bdata.accel_scale
                        gx = gx_r * bdata.gyro_scale
                        gy = gy_r * bdata.gyro_scale
                        gz = gz_r * bdata.gyro_scale

                        bdata.sample_count += 1
                        bdata.t_buf.append(now_s)
                        bdata.az_buf.append(az)
                        bdata.gz_buf.append(gz)

                        bdata.samples_all.append((seq, wheel_side, int(now_ms), t_us, round(now_ms, 3), ax, ay, az, gx, gy, gz, 0))

            def sync_cb(sender, data: bytearray):
                if not data:
                    return
                if data[0] == 0x10 and len(data) >= 5:
                    with self.lock:
                        bdata.drop_count += struct.unpack_from("<I", data, 1)[0]
                elif data[0] == 0x60 and len(data) >= 20:
                    _, _, _, q_drops, fails, _ = struct.unpack_from("<BIIIIH", data, 1)
                    with self.lock:
                        bdata.drop_count = q_drops
                        bdata.transport_failures = fails

            await client.start_notify(IMU_DATA_UUID, imu_cb)
            await client.start_notify(SYNC_UUID, sync_cb)

        tasks = []
        if left_addr:
            tasks.append(connect_one(left_addr, 'L'))
        if right_addr:
            tasks.append(connect_one(right_addr, 'R'))

        await asyncio.gather(*tasks)
        self.is_connected = True
        sides_str = ", ".join(self.boards.keys())
        self.status_msg = f"Connected to [{sides_str}]"
        return f"Success: Connected to {sides_str}"

    async def start_streaming(self):
        start_cmd = struct.pack("<BI", 0x01, 0)
        for client in self.clients.values():
            await client.write_gatt_char(CONTROL_UUID, start_cmd, response=True)
        self.is_streaming = True
        self.status_msg = "Streaming Live IMU..."

    async def stop_streaming(self):
        stop_cmd = struct.pack("<B", 0x02)
        for client in self.clients.values():
            try:
                await client.write_gatt_char(CONTROL_UUID, stop_cmd, response=True)
            except Exception:
                pass
        self.is_streaming = False
        self.status_msg = "Streaming Stopped"

    def save_csv(self) -> Optional[str]:
        all_rows = []
        with self.lock:
            for bdata in self.boards.values():
                all_rows.extend(bdata.samples_all)

        if not all_rows:
            return None

        out_path = Path("tools/test_data") / f"pc_dual_gui_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv"
        out_path.parent.mkdir(parents=True, exist_ok=True)

        all_rows.sort(key=lambda r: r[4])
        header = ["seq", "wheel", "timestamp_app_ms", "timestamp_device_us", "timestamp_synced_ms", "ax", "ay", "az", "gx", "gy", "gz", "marker"]

        with open(out_path, "w", newline="", encoding="utf-8") as f:
            w = csv.writer(f)
            w.writerow(header)
            w.writerows(all_rows)

        return str(out_path.resolve())


# ── Tkinter GUI App ───────────────────────────────────────────────────────────

class DualBoardGuiApp:
    def __init__(self, root: tk.Tk):
        self.root = root
        self.root.title("WheelAthlete — Real-time Dual Board BLE Diagnoser")
        self.root.geometry("1100x720")
        self.root.configure(bg="#1e1e2e")

        self.backend = BleBackendThread()
        self.backend.start()

        self._setup_styles()
        self._build_ui()

        # Update timers and auto-connect on startup
        self.last_time = time.time()
        self.last_counts = {}
        self.root.after(50, self._update_loop)
        self.root.after(300, self._on_connect)

    def _setup_styles(self):
        style = ttk.Style()
        style.theme_use("clam")
        style.configure(".", background="#1e1e2e", foreground="#cdd6f4", font=("Segoe UI", 10))
        style.configure("TButton", font=("Segoe UI", 10, "bold"), padding=6)
        style.configure("TLabel", background="#1e1e2e", foreground="#cdd6f4")
        style.configure("Header.TLabel", font=("Segoe UI", 14, "bold"), foreground="#89b4fa")
        style.configure("Status.TLabel", font=("Segoe UI", 10, "italic"), foreground="#a6adc8")

    def _build_ui(self):
        # Top control frame
        ctrl_frame = ttk.Frame(self.root, padding=10)
        ctrl_frame.pack(fill=tk.X)

        title = ttk.Label(ctrl_frame, text="⚡ WheelAthlete Dual-Board Real-time IMU", style="Header.TLabel")
        title.pack(side=tk.LEFT, padx=10)

        self.btn_connect = ttk.Button(ctrl_frame, text="🔌 Connect Boards", command=self._on_connect)
        self.btn_connect.pack(side=tk.LEFT, padx=5)

        self.btn_start = ttk.Button(ctrl_frame, text="▶️ Start Stream", command=self._on_start, state=tk.DISABLED)
        self.btn_start.pack(side=tk.LEFT, padx=5)

        self.btn_stop = ttk.Button(ctrl_frame, text="⏹️ Stop & Save CSV", command=self._on_stop, state=tk.DISABLED)
        self.btn_stop.pack(side=tk.LEFT, padx=5)

        self.lbl_status = ttk.Label(ctrl_frame, text="Status: Ready", style="Status.TLabel")
        self.lbl_status.pack(side=tk.RIGHT, padx=10)

        # Telemetry info bar
        info_frame = ttk.Frame(self.root, padding=(10, 0))
        info_frame.pack(fill=tk.X)

        self.lbl_left_info = ttk.Label(info_frame, text="Left [L]: Disconnected", font=("Consolas", 10, "bold"), foreground="#89b4fa")
        self.lbl_left_info.pack(side=tk.LEFT, expand=True)
        self.lbl_right_info = ttk.Label(info_frame, text="Right [R]: Disconnected", font=("Consolas", 10, "bold"), foreground="#f38ba8")
        self.lbl_right_info.pack(side=tk.RIGHT, expand=True)

        # Matplotlib Matplot Canvas
        self.fig, (self.ax_accel, self.ax_gyro) = plt.subplots(2, 1, figsize=(10, 5), sharex=True)
        self.fig.patch.set_facecolor("#181825")

        for ax in (self.ax_accel, self.ax_gyro):
            ax.set_facecolor("#1e1e2e")
            ax.tick_params(colors="#a6adc8", labelsize=9)
            ax.spines['bottom'].set_color('#45475a')
            ax.spines['top'].set_color('#45475a')
            ax.spines['left'].set_color('#45475a')
            ax.spines['right'].set_color('#45475a')
            ax.grid(True, color="#313244", linestyle="--", alpha=0.5)

        self.ax_accel.set_ylabel("Accel Az (g)", color="#cdd6f4")
        self.ax_gyro.set_ylabel("Gyro Gz (dps)", color="#cdd6f4")
        self.ax_gyro.set_xlabel("Time (s)", color="#cdd6f4")

        self.ax_accel.set_ylim(-3.0, 3.0)
        self.ax_gyro.set_ylim(-500.0, 500.0)

        # Lines for Left (Blue) and Right (Red)
        self.line_l_az, = self.ax_accel.plot([], [], label="Left Az", color="#89b4fa", linewidth=1.5)
        self.line_r_az, = self.ax_accel.plot([], [], label="Right Az", color="#f38ba8", linewidth=1.5)

        self.line_l_gz, = self.ax_gyro.plot([], [], label="Left Gz", color="#89b4fa", linewidth=1.5)
        self.line_r_gz, = self.ax_gyro.plot([], [], label="Right Gz", color="#f38ba8", linewidth=1.5)

        self.ax_accel.legend(loc="upper right", facecolor="#181825", edgecolor="#45475a", labelcolor="#cdd6f4")
        self.ax_gyro.legend(loc="upper right", facecolor="#181825", edgecolor="#45475a", labelcolor="#cdd6f4")

        self.fig.tight_layout()

        self.canvas = FigureCanvasTkAgg(self.fig, master=self.root)
        self.canvas.get_tk_widget().pack(fill=tk.BOTH, expand=True, padx=10, pady=10)

    def _on_connect(self):
        self.btn_connect.config(state=tk.DISABLED)
        self.lbl_status.config(text="Status: Scanning & Connecting...")

        def _task():
            future = self.backend.async_run(self.backend.scan_and_connect())
            try:
                res = future.result(timeout=15.0)
                self.root.after(0, lambda r=res: self._on_connect_done(r))
            except Exception as e:
                err_msg = f"Error: {e}"
                self.root.after(0, lambda msg=err_msg: self._on_connect_done(msg))

        threading.Thread(target=_task, daemon=True).start()

    def _on_connect_done(self, result: str):
        self.btn_connect.config(state=tk.NORMAL)
        self.lbl_status.config(text=f"Status: {result}")
        if self.backend.is_connected:
            self.btn_start.config(state=tk.NORMAL)
            # Auto-start streaming immediately after connection
            self._on_start()

    def _on_start(self):
        self.backend.async_run(self.backend.start_streaming())
        self.btn_start.config(state=tk.DISABLED)
        self.btn_stop.config(state=tk.NORMAL)

    def _on_stop(self):
        self.backend.async_run(self.backend.stop_streaming())
        csv_path = self.backend.save_csv()
        self.btn_start.config(state=tk.NORMAL)
        self.btn_stop.config(state=tk.DISABLED)

        if csv_path:
            messagebox.showinfo("Session Saved", f"Session CSV saved successfully to:\n{csv_path}")

    def _update_loop(self):
        now = time.time()
        dt = now - self.last_time
        self.last_time = now

        self.lbl_status.config(text=f"Status: {self.backend.status_msg}")
        has_data = False

        with self.backend.lock:
            # Update telemetry strings
            if 'L' in self.backend.boards:
                st = self.backend.boards['L']
                d_cnt = st.sample_count - self.last_counts.get('L', 0)
                self.last_counts['L'] = st.sample_count
                hz = d_cnt / dt if dt > 0 else 0.0
                self.lbl_left_info.config(text=f"L: {hz:5.1f} Hz | Total: {st.sample_count:5d} | Drops: {st.drop_count:2d} | Fails: {st.transport_failures:2d}")

                if len(st.t_buf) > 1:
                    t0 = st.t_buf[0]
                    rel_t = [t - t0 for t in st.t_buf]
                    self.line_l_az.set_data(rel_t, list(st.az_buf))
                    self.line_l_gz.set_data(rel_t, list(st.gz_buf))
                    has_data = True

            if 'R' in self.backend.boards:
                st = self.backend.boards['R']
                d_cnt = st.sample_count - self.last_counts.get('R', 0)
                self.last_counts['R'] = st.sample_count
                hz = d_cnt / dt if dt > 0 else 0.0
                self.lbl_right_info.config(text=f"R: {hz:5.1f} Hz | Total: {st.sample_count:5d} | Drops: {st.drop_count:2d} | Fails: {st.transport_failures:2d}")

                if len(st.t_buf) > 1:
                    t0 = st.t_buf[0]
                    rel_t = [t - t0 for t in st.t_buf]
                    self.line_r_az.set_data(rel_t, list(st.az_buf))
                    self.line_r_gz.set_data(rel_t, list(st.gz_buf))
        # Relim axes
        for ax in (self.ax_accel, self.ax_gyro):
            ax.relim()
            ax.autoscale_view()

        self.canvas.draw_idle()
        self.root.after(50, self._update_loop)


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    root = tk.Tk()
    app = DualBoardGuiApp(root)
    root.mainloop()

if __name__ == "__main__":
    main()
