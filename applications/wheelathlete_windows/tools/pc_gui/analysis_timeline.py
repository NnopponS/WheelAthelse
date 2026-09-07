"""Native offline analysis cursor/window panel; no inference or acquisition work."""

from __future__ import annotations

import json
import math
from pathlib import Path
from threading import Thread

from PySide6.QtCore import QPointF, Qt, Signal
from PySide6.QtGui import QPalette, QPen
from PySide6.QtCharts import QChart, QChartView, QLineSeries, QValueAxis
from PySide6.QtWidgets import (
    QComboBox,
    QDoubleSpinBox,
    QFileDialog,
    QGridLayout,
    QHBoxLayout,
    QLabel,
    QPushButton,
    QSlider,
    QVBoxLayout,
    QWidget,
)

from .analysis_contract import validate_analysis, window_statistics
from .analysis_export import export_analysis
from .widgets import style_chart_surface

CHANNELS = (
    ("signed_speed_mps", "Signed forward speed (m/s)", 1.0),
    ("speed_mps", "Speed magnitude (m/s)", 1.0),
    ("longitudinal_accel_mps2", "Longitudinal acceleration (m/s2)", 1.0),
    ("yaw_rad", "Unwrapped chair yaw (deg)", 180 / math.pi),
    ("yaw_rate_radps", "Yaw rate (deg/s)", 180 / math.pi),
    ("speed_change_mps2", "Speed-magnitude change (m/s2)", 1.0),
)


def _fmt(v, unit="", digits=2):
    return "Unavailable" if v is None else f"{v:.{digits}f}{unit}"


class AnalysisTimeline(QWidget):
    cursor_changed = Signal(int)
    window_changed = Signal(int, int)
    export_ready = Signal(str)
    export_failed = Signal(str)

    def __init__(self, parent=None):
        super().__init__(parent)
        self.analysis = None
        self.last_statistics = None
        self._exporting = False
        self.setMinimumWidth(340)
        layout = QVBoxLayout(self)
        layout.setContentsMargins(6, 6, 6, 6)
        layout.setSpacing(4)
        self.scope = QLabel("Time and window review")
        self.scope.setWordWrap(True)
        self.scope.setObjectName("cardTitle")
        layout.addWidget(self.scope)
        self.time_label = QLabel("No analysis timeline")
        self.time_label.setAccessibleName("analysisSelectedTime")
        layout.addWidget(self.time_label)
        self.cursor = QSlider(Qt.Orientation.Horizontal)
        self.cursor.setAccessibleName("analysisTimeSlider")
        self.cursor.setSingleStep(1)
        self.cursor.setPageStep(20)
        layout.addWidget(self.cursor)
        self.selected_label = QLabel(
            "Speed, acceleration and orientation will appear here."
        )
        self.selected_label.setAccessibleName("analysisSelectedMetrics")
        self.selected_label.setWordWrap(True)
        layout.addWidget(self.selected_label)
        self.channel = QComboBox()
        self.channel.setAccessibleName("analysisChannel")
        for _, title, _ in CHANNELS:
            self.channel.addItem(title)
        layout.addWidget(self.channel)
        self.chart = QChart()
        self.chart.legend().hide()
        self.xaxis, self.yaxis = QValueAxis(), QValueAxis()
        self.xaxis.setTitleText("Recording time (s)")
        self.xaxis.setLabelFormat("%.2f")
        self.yaxis.setLabelFormat("%.2f")
        self.chart.addAxis(self.xaxis, Qt.AlignmentFlag.AlignBottom)
        self.chart.addAxis(self.yaxis, Qt.AlignmentFlag.AlignLeft)
        self.chart_view = QChartView(self.chart)
        self.chart_view.setAccessibleName("analysisTimeSeriesChart")
        self.chart_view.setMinimumHeight(180)
        style_chart_surface(self.chart, self.chart_view)
        layout.addWidget(self.chart_view, 1)
        self.cursor_line = QLineSeries()
        self.start_line, self.stop_line = QLineSeries(), QLineSeries()
        color = self.palette().color(QPalette.ColorRole.Highlight)
        self.cursor_line.setPen(QPen(color, 1.5))
        for line in (self.start_line, self.stop_line):
            line.setPen(QPen(color, 1.0, Qt.PenStyle.DashLine))
        for line in (self.cursor_line, self.start_line, self.stop_line):
            self.chart.addSeries(line)
            line.attachAxis(self.xaxis)
            line.attachAxis(self.yaxis)
        self._traces = []
        self.start, self.stop = QDoubleSpinBox(), QDoubleSpinBox()
        grid = QGridLayout()
        for i, (name, control) in enumerate(
            (("Window start", self.start), ("Window end", self.stop))
        ):
            control.setDecimals(6)
            control.setSuffix(" s")
            control.setSingleStep(0.05)
            control.setAccessibleName(
                "analysisWindowStart" if i == 0 else "analysisWindowEnd"
            )
            grid.addWidget(QLabel(name), 0, i)
            grid.addWidget(control, 1, i)
        layout.addLayout(grid)
        self.summary = QLabel("Window summaries use all samples, not chart decimation.")
        self.summary.setAccessibleName("analysisWindowSummary")
        self.summary.setWordWrap(True)
        layout.addWidget(self.summary)
        self.quality = QLabel("")
        self.quality.setWordWrap(True)
        self.quality.setAccessibleName("analysisQualityStatus")
        layout.addWidget(self.quality)
        self.details_button = QPushButton("Show timing and quality details")
        self.details_button.setCheckable(True)
        self.details_button.setAccessibleName("analysisQualityDetailsButton")
        self.details = QLabel("")
        self.details.setWordWrap(True)
        self.details.setTextInteractionFlags(Qt.TextInteractionFlag.TextSelectableByMouse)
        self.details.hide()
        self.details_button.toggled.connect(self.details.setVisible)
        layout.addWidget(self.details_button)
        layout.addWidget(self.details)
        self.export_button = QPushButton("Export timeline + metadata...")
        self.export_button.setAccessibleName("exportAnalysisButton")
        reset = QPushButton("Full window")
        reset.setAccessibleName("analysisResetWindow")
        buttons = QHBoxLayout()
        buttons.addWidget(reset)
        buttons.addWidget(self.export_button)
        layout.addLayout(buttons)
        self.export_status = QLabel(
            "CSV contains the entire timeline. The selected window is recorded in JSON."
        )
        self.export_status.setWordWrap(True)
        layout.addWidget(self.export_status)
        self.cursor.valueChanged.connect(self._cursor_changed)
        self.start.valueChanged.connect(self._window_changed)
        self.stop.valueChanged.connect(self._window_changed)
        self.channel.currentIndexChanged.connect(self._plot_channel)
        self.export_button.clicked.connect(self._choose_export)
        self.export_ready.connect(self._export_ready)
        self.export_failed.connect(self._export_failed)
        reset.clicked.connect(self.full_window)
        self.reset_button = reset
        self.set_analysis(None)

    def set_analysis(self, analysis):
        if analysis is not None:
            validate_analysis(analysis)
        # Own a detached full-resolution snapshot. Window selection never mutates it.
        self.analysis = (
            json.loads(json.dumps(analysis, allow_nan=False))
            if analysis is not None
            else None
        )
        enabled = self.analysis is not None
        for control in (
            self.cursor,
            self.channel,
            self.start,
            self.stop,
            self.reset_button,
        ):
            control.setEnabled(enabled)
        self.export_button.setEnabled(enabled and not self._exporting)
        if not enabled:
            self.last_statistics = None
            self.time_label.setText("No analysis timeline")
            self.selected_label.setText(
                "Select a finalized recording and generate an analysis."
            )
            self.summary.setText("")
            self.quality.setText("")
            for series in self._traces:
                self.chart.removeSeries(series)
                series.deleteLater()
            self._traces = []
            for line in (self.cursor_line, self.start_line, self.stop_line):
                line.clear()
            return
        meta = self.analysis["metadata"]
        warnings = meta.get("warnings", [])
        self.details.setText(
            "Time basis: " + str(meta.get("time_basis", "unknown")) + "\n"
            + "XY frame: " + str(meta.get("xy_frame", "unknown")) + "\n"
            + "Yaw frame: " + str(meta.get("yaw_frame", "unavailable")) + "\n"
            + "\n".join(str(v) for v in warnings)
        )
        rows = self.analysis["samples"]
        self.cursor.setRange(0, len(rows) - 1)
        for control in (self.start, self.stop):
            control.blockSignals(True)
            control.setRange(rows[0]["time_s"], rows[-1]["time_s"])
            control.blockSignals(False)
        if all(p["signed_speed_mps"] is None for p in rows):
            self.channel.setCurrentIndex(1)
        self.full_window()
        self._plot_channel()
        self.cursor.setValue(0)
        self._cursor_changed(0)

    def full_window(self):
        if self.analysis is None:
            return
        self.start.blockSignals(True)
        self.stop.blockSignals(True)
        self.start.setValue(self.analysis["samples"][0]["time_s"])
        self.stop.setValue(self.analysis["samples"][-1]["time_s"])
        self.start.blockSignals(False)
        self.stop.blockSignals(False)
        self._window_changed()

    def _plot_channel(self, *_):
        if self.analysis is None:
            return
        for series in self._traces:
            self.chart.removeSeries(series)
            series.deleteLater()
        self._traces = []
        field, label, scale = CHANNELS[self.channel.currentIndex()]
        rows = self.analysis["samples"]
        values = [p[field] * scale for p in rows if p[field] is not None]
        low, high = (min(values), max(values)) if values else (-1.0, 1.0)
        pad = max((high - low) * 0.08, 0.05)
        self.yaxis.setRange(low - pad, high + pad)
        self.xaxis.setRange(rows[0]["time_s"], rows[-1]["time_s"])
        self.chart.setTitle(label if values else label + " - unavailable")
        run = []

        def flush():
            if not run:
                return
            series = QLineSeries()
            stride = max(1, len(run) // 2500)
            display = run[::stride]
            if display[-1] != run[-1]:
                display.append(run[-1])
            series.replace(display)
            self.chart.addSeries(series)
            series.attachAxis(self.xaxis)
            series.attachAxis(self.yaxis)
            self._traces.append(series)
            run.clear()

        for p in rows:
            if p[field] is None:
                flush()
            else:
                run.append(QPointF(p["time_s"], p[field] * scale))
        flush()
        self._cursor_changed(self.cursor.value())
        self._window_changed()

    def _cursor_changed(self, index):
        if self.analysis is None:
            return
        row = self.analysis["samples"][index]
        self.time_label.setText(
            f"Time {row['time_s']:.3f} s | sample {index + 1}/{len(self.analysis['samples'])}"
        )
        self.selected_label.setText(
            f"Signed speed {_fmt(row['signed_speed_mps'], ' m/s')} | magnitude {_fmt(row['speed_mps'], ' m/s')}\n"
            f"Long. accel {_fmt(row['longitudinal_accel_mps2'], ' m/s2')}\n"
            f"Yaw {_fmt(None if row['yaw_rad'] is None else math.degrees(row['yaw_rad']), ' deg')} | "
            f"yaw rate {_fmt(None if row['yaw_rate_radps'] is None else math.degrees(row['yaw_rate_radps']), ' deg/s')}"
        )
        self.cursor_line.replace(
            [
                QPointF(row["time_s"], self.yaxis.min()),
                QPointF(row["time_s"], self.yaxis.max()),
            ]
        )
        flags = row["quality_flags"]
        self.quality.setText(
            "Experimental / clock uncertainty. "
            + (
                ", ".join(flags)
                if flags
                else "No local input flag; not a validity certificate."
            )
        )
        self.cursor_changed.emit(index)

    def _window_changed(self, *_):
        if self.analysis is None:
            return
        if self.stop.value() < self.start.value():
            if self.sender() is self.stop:
                self.start.setValue(self.stop.value())
            else:
                self.stop.setValue(self.start.value())
        # Spinboxes round at 6 decimal places; snap to actual sample-center indices.
        from .analysis_contract import nearest_index

        ts = [p["time_s"] for p in self.analysis["samples"]]
        lo, hi = (
            nearest_index(ts, self.start.value()),
            nearest_index(ts, self.stop.value()),
        )
        stats = window_statistics(self.analysis, ts[lo], ts[hi])
        self.last_statistics = stats
        speed = stats["metrics"]["speed_mps"]
        self.summary.setText(
            f"Window: {stats['samples']} samples / {stats['duration_s']:.3f} s / {stats['path_length_m']:.3f} m estimated path\n"
            f"Mean speed {_fmt(speed['mean'], ' m/s')} | max {_fmt(speed['max'], ' m/s')}\n"
            f"Net yaw {_fmt(None if stats['net_yaw_rad'] is None else math.degrees(stats['net_yaw_rad']), ' deg')} | "
            f"accel support {stats['metrics']['longitudinal_accel_mps2']['samples']} samples"
        )
        for line, time in ((self.start_line, ts[lo]), (self.stop_line, ts[hi])):
            line.replace(
                [QPointF(time, self.yaxis.min()), QPointF(time, self.yaxis.max())]
            )
        self.window_changed.emit(lo, hi)

    def export_to(self, parent: Path) -> Path:
        if self.analysis is None:
            raise ValueError("No analysis to export")
        stats = self.last_statistics
        rows = self.analysis["samples"]
        return export_analysis(
            self.analysis,
            parent,
            start_s=rows[stats["start_index"]]["time_s"],
            stop_s=rows[stats["stop_index_exclusive"] - 1]["time_s"],
        )

    def _choose_export(self):
        if self.analysis is None or self._exporting:
            return
        destination = QFileDialog.getExistingDirectory(
            self,
            "Export derived analysis to a NEW folder",
            str(Path.home() / "Documents"),
        )
        if not destination:
            return
        analysis = self.analysis
        stats = self.last_statistics
        rows = analysis["samples"]
        start, stop = (
            rows[stats["start_index"]]["time_s"],
            rows[stats["stop_index_exclusive"] - 1]["time_s"],
        )
        self._exporting = True
        self.export_button.setEnabled(False)
        self.export_status.setText(
            "Writing derived files without changing the recording..."
        )

        def work():
            try:
                out = export_analysis(
                    analysis, Path(destination), start_s=start, stop_s=stop
                )
                self.export_ready.emit(str(out))
            except Exception as exc:
                try:
                    self.export_failed.emit(str(exc))
                except RuntimeError:
                    pass  # View was closed; files remain independently valid.

        Thread(target=work, name="wheelathlete-analysis-export", daemon=True).start()

    def _export_ready(self, path):
        self._exporting = False
        self.export_button.setEnabled(self.analysis is not None)
        self.export_status.setText("Saved: " + path)

    def _export_failed(self, error):
        self._exporting = False
        self.export_button.setEnabled(self.analysis is not None)
        self.export_status.setText("Export failed: " + error)
