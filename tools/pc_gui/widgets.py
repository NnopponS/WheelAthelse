from __future__ import annotations

from collections.abc import Callable
from typing import Any

from PySide6.QtCharts import QChart, QChartView, QLineSeries, QValueAxis
from PySide6.QtCore import QPointF, Qt
from PySide6.QtGui import QColor, QFont, QPainter, QPen
from PySide6.QtWidgets import (
    QFrame,
    QGridLayout,
    QHBoxLayout,
    QLabel,
    QSizePolicy,
    QVBoxLayout,
    QWidget,
)

from .controller import BaseController
from .state import BoardView, PreviewSample


def fmt(value: Any, suffix: str = "", digits: int = 1) -> str:
    if value is None:
        return "—"
    if isinstance(value, float):
        return f"{value:.{digits}f}{suffix}"
    return f"{value}{suffix}"


class Card(QFrame):
    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.setObjectName("card")
        self.setFrameShape(QFrame.Shape.NoFrame)


class MetricTile(Card):
    def __init__(self, label: str, value: str = "—", parent: QWidget | None = None) -> None:
        super().__init__(parent)
        layout = QVBoxLayout(self)
        layout.setContentsMargins(14, 12, 14, 12)
        layout.setSpacing(3)
        self.label = QLabel(label)
        self.label.setObjectName("metricLabel")
        self.value = QLabel(value)
        self.value.setObjectName("metricValue")
        self.value.setTextInteractionFlags(Qt.TextInteractionFlag.TextSelectableByMouse)
        layout.addWidget(self.label)
        layout.addWidget(self.value)

    def set_value(self, value: str) -> None:
        self.value.setText(value)


class BoardSummaryCard(Card):
    def __init__(self, side: str, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.side = side
        root = QVBoxLayout(self)
        root.setContentsMargins(18, 16, 18, 16)
        root.setSpacing(12)
        header = QHBoxLayout()
        self.title = QLabel(f"{side} wheel")
        self.title.setObjectName("cardTitle")
        self.status = QLabel("OFFLINE")
        self.status.setObjectName("statusPill")
        header.addWidget(self.title)
        header.addStretch(1)
        header.addWidget(self.status)
        root.addLayout(header)

        self.device = QLabel("Not connected")
        self.device.setObjectName("mutedText")
        root.addWidget(self.device)

        grid = QGridLayout()
        grid.setHorizontalSpacing(8)
        grid.setVerticalSpacing(8)
        self.metrics: dict[str, MetricTile] = {}
        definitions = [
            ("rate", "Samples/s"),
            ("rssi", "RSSI"),
            ("mtu", "MTU"),
            ("battery", "Battery"),
            ("loss", "Data loss"),
            ("queue", "Queue"),
            ("rtt", "Best RTT"),
            ("drift", "Drift"),
        ]
        for index, (key, label) in enumerate(definitions):
            tile = MetricTile(label)
            self.metrics[key] = tile
            grid.addWidget(tile, index // 4, index % 4)
        root.addLayout(grid)

    def update_board(self, board: BoardView, *, active: bool = False) -> None:
        self.title.setText(f"{board.side} wheel")
        accel_names = {0: "±2g", 1: "±4g", 2: "±8g", 3: "±16g"}
        gyro_names = {0: "±250°/s", 1: "±500°/s", 2: "±1000°/s", 3: "±2000°/s"}
        ranges = ""
        if board.accel_range in accel_names and board.gyro_range in gyro_names:
            ranges = f"   •   {accel_names[board.accel_range]} / {gyro_names[board.gyro_range]}"
        self.device.setText(
            f"{board.name}   •   FW {board.firmware}{ranges}"
            if board.connected
            else "Not connected"
        )
        if board.connected:
            self.status.setText(
                "STREAMING"
                if active and board.healthy
                else "CONNECTED"
                if board.healthy
                else "CHECK"
            )
            self.status.setProperty("state", "good" if board.healthy else "warning")
        else:
            self.status.setText("OFFLINE")
            self.status.setProperty("state", "offline")
        self.status.style().unpolish(self.status)
        self.status.style().polish(self.status)
        self.metrics["rate"].set_value(fmt(board.samples_hz, " Hz", 2))
        self.metrics["rssi"].set_value(fmt(board.rssi, " dBm", 0))
        self.metrics["mtu"].set_value(fmt(board.mtu, "", 0))
        self.metrics["battery"].set_value(fmt(board.battery_percent, "%", 0))
        self.metrics["loss"].set_value(str(board.loss_count))
        self.metrics["queue"].set_value(f"{board.queue_depth} / {board.queue_high_water}")
        self.metrics["rtt"].set_value(fmt(board.best_rtt_ms, " ms", 2))
        self.metrics["drift"].set_value(fmt(board.drift_ppm, " ppm", 2))


class CurrentSensorCard(Card):
    def __init__(self, side: str, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.side = side
        layout = QVBoxLayout(self)
        layout.setContentsMargins(16, 14, 16, 14)
        layout.setSpacing(9)
        title = QLabel(f"Wheel {side} — current sample")
        title.setObjectName("cardTitle")
        layout.addWidget(title)
        grid = QGridLayout()
        grid.setSpacing(8)
        self.values: dict[str, MetricTile] = {}
        labels = [
            ("ax", "Accel X"),
            ("ay", "Accel Y"),
            ("az", "Accel Z"),
            ("gx", "Gyro X"),
            ("gy", "Gyro Y"),
            ("gz", "Gyro Z"),
        ]
        for index, (key, label) in enumerate(labels):
            tile = MetricTile(label)
            self.values[key] = tile
            grid.addWidget(tile, index // 3, index % 3)
        layout.addLayout(grid)
        self.seq = QLabel("Sequence —")
        self.seq.setObjectName("mutedText")
        layout.addWidget(self.seq)

    def update_sample(
        self,
        sample: PreviewSample | None,
        *,
        accel_scale: float,
        gyro_scale: float,
    ) -> None:
        if sample is None:
            for tile in self.values.values():
                tile.set_value("—")
            self.seq.setText("Sequence —")
            return
        self.values["ax"].set_value(f"{sample.ax * accel_scale:+.3f} g")
        self.values["ay"].set_value(f"{sample.ay * accel_scale:+.3f} g")
        self.values["az"].set_value(f"{sample.az * accel_scale:+.3f} g")
        self.values["gx"].set_value(f"{sample.gx * gyro_scale:+.1f} °/s")
        self.values["gy"].set_value(f"{sample.gy * gyro_scale:+.1f} °/s")
        self.values["gz"].set_value(f"{sample.gz * gyro_scale:+.1f} °/s")
        self.seq.setText(f"Sequence {sample.seq:,}   •   device {sample.device_us:,} µs")


class MultiAxisChart(Card):
    def __init__(
        self,
        title: str,
        y_label: str,
        extractor: Callable[[PreviewSample, str, float, float], float],
        side: str | None = None,
        parent: QWidget | None = None,
    ) -> None:
        super().__init__(parent)
        self.extractor = extractor
        self.side = side
        outer = QVBoxLayout(self)
        outer.setContentsMargins(8, 8, 8, 8)
        outer.setSpacing(2)

        self.chart = QChart()
        self.chart.setTitle(title)
        title_font = QFont()
        title_font.setPointSize(10)
        title_font.setBold(True)
        self.chart.setTitleFont(title_font)
        self.chart.legend().setVisible(True)
        self.chart.legend().setAlignment(Qt.AlignmentFlag.AlignBottom)
        self.chart.setAnimationOptions(QChart.AnimationOption.NoAnimation)

        self.x_axis = QValueAxis()
        self.x_axis.setTitleText("Recent time (s)")
        self.x_axis.setRange(-30, 0)
        self.x_axis.setTickCount(7)
        self.y_axis = QValueAxis()
        self.y_axis.setTitleText(y_label)
        self.y_axis.setRange(-1, 1)
        self.chart.addAxis(self.x_axis, Qt.AlignmentFlag.AlignBottom)
        self.chart.addAxis(self.y_axis, Qt.AlignmentFlag.AlignLeft)

        axis_colors = {
            "X": QColor("#0284c7"),  # Sky Blue
            "Y": QColor("#16a34a"),  # Emerald Green
            "Z": QColor("#ea580c"),  # Coral Orange
        }

        self.series: dict[tuple[str, str], QLineSeries] = {}
        sides = (side,) if side in ("L", "R") else ("L", "R")
        for s in sides:
            for axis in ("X", "Y", "Z"):
                series = QLineSeries()
                name = f"{axis}" if side else f"{s} {axis}"
                series.setName(name)
                pen = QPen(axis_colors[axis])
                pen.setWidthF(1.8)
                series.setPen(pen)
                self.chart.addSeries(series)
                series.attachAxis(self.x_axis)
                series.attachAxis(self.y_axis)
                self.series[(s, axis)] = series
        view = QChartView(self.chart)
        view.setRenderHint(QPainter.RenderHint.Antialiasing, False)
        view.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Expanding)
        view.setMinimumHeight(170)
        outer.addWidget(view)

    def update_from_controller(self, controller: BaseController) -> None:
        all_values: list[float] = []
        sides = (self.side,) if self.side in ("L", "R") else ("L", "R")
        for side in sides:
            samples = controller.preview_buffer(side).values()
            board = controller.state.boards[side]
            if not samples:
                for axis in ("X", "Y", "Z"):
                    if (side, axis) in self.series:
                        self.series[(side, axis)].replace([])
                continue
            latest_ns = samples[-1].pc_ns
            for axis in ("X", "Y", "Z"):
                points: list[QPointF] = []
                for sample in samples:
                    x = (sample.pc_ns - latest_ns) / 1_000_000_000
                    y = self.extractor(sample, axis, board.accel_scale, board.gyro_scale)
                    points.append(QPointF(x, y))
                    all_values.append(y)
                if (side, axis) in self.series:
                    self.series[(side, axis)].replace(points)
        if all_values:
            limit = max(0.05, max(abs(value) for value in all_values)) * 1.12
            self.y_axis.setRange(-limit, limit)

def accel_value(sample: PreviewSample, axis: str, accel_scale: float, _gyro_scale: float) -> float:
    raw = {"X": sample.ax, "Y": sample.ay, "Z": sample.az}[axis]
    return raw * accel_scale


def gyro_value(sample: PreviewSample, axis: str, _accel_scale: float, gyro_scale: float) -> float:
    raw = {"X": sample.gx, "Y": sample.gy, "Z": sample.gz}[axis]
    return raw * gyro_scale
