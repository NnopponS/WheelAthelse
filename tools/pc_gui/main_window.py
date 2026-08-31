from __future__ import annotations

import os
from pathlib import Path
from typing import Any

from PySide6.QtCore import QTimer, Qt, Signal
from PySide6.QtGui import QAction, QCloseEvent, QDesktopServices
from PySide6.QtCore import QUrl
from PySide6.QtWidgets import (
    QAbstractItemView,
    QApplication,
    QComboBox,
    QFileDialog,
    QFormLayout,
    QFrame,
    QGridLayout,
    QHBoxLayout,
    QHeaderView,
    QLabel,
    QLineEdit,
    QListWidget,
    QListWidgetItem,
    QMainWindow,
    QMessageBox,
    QPushButton,
    QSpinBox,
    QStackedWidget,
    QTableWidget,
    QTableWidgetItem,
    QTextEdit,
    QTreeWidget,
    QTreeWidgetItem,
    QVBoxLayout,
    QWidget,
)

from .controller import BaseController
from .experiments import ExperimentTemplate
from .state import AppViewState
from .widgets import (
    BoardSummaryCard,
    Card,
    CurrentSensorCard,
    MultiAxisChart,
    accel_value,
    fmt,
    gyro_value,
)


NAV_ITEMS = [
    ("Dashboard", "Overview & connect"),
    ("Live", "Realtime sensors"),
    ("Record", "Synchronized recording"),
    ("Experiments", "Reusable protocols"),
    ("Sessions", "Saved data"),
    ("Diagnostics", "Data integrity"),
]


APP_QSS = """
QWidget {
    font-family: "Segoe UI";
    font-size: 13px;
    color: #172033;
}
QMainWindow, QWidget#root { background: #f5f7fb; }
QFrame#sidebar { background: #111827; border: none; }
QLabel#brand { color: white; font-size: 22px; font-weight: 700; }
QLabel#brandSub { color: #94a3b8; font-size: 11px; }
QListWidget#nav {
    background: transparent; border: none; color: #cbd5e1; outline: none;
}
QListWidget#nav::item { padding: 12px 14px; margin: 2px 7px; border-radius: 8px; }
QListWidget#nav::item:selected { background: #0f766e; color: white; }
QListWidget#nav::item:hover:!selected { background: #1f2937; }
QFrame#card { background: white; border: 1px solid #e2e8f0; border-radius: 12px; }
QLabel#pageTitle { font-size: 24px; font-weight: 700; }
QLabel#pageSub { color: #64748b; }
QLabel#cardTitle { font-size: 16px; font-weight: 700; }
QLabel#mutedText, QLabel#metricLabel { color: #64748b; }
QLabel#metricLabel { font-size: 11px; }
QLabel#metricValue { font-size: 17px; font-weight: 700; }
QLabel#statusPill {
    padding: 4px 9px; border-radius: 9px; font-size: 10px; font-weight: 700;
    background: #e2e8f0; color: #475569;
}
QLabel#statusPill[state="good"] { background: #dcfce7; color: #166534; }
QLabel#statusPill[state="warning"] { background: #fef3c7; color: #92400e; }
QLabel#statusPill[state="offline"] { background: #e2e8f0; color: #475569; }
QLabel#daemonBadge { padding: 6px 10px; border-radius: 10px; background: #fee2e2; color: #991b1b; font-weight: 600; }
QLabel#daemonBadge[online="true"] { background: #dcfce7; color: #166534; }
QLabel#recordBadge { padding: 6px 10px; border-radius: 10px; background: #e2e8f0; color: #475569; font-weight: 700; }
QLabel#recordBadge[recording="true"] { background: #fee2e2; color: #b91c1c; }
QLabel#demoBadge { padding: 6px 10px; border-radius: 10px; background: #fef3c7; color: #92400e; font-weight: 800; }
QPushButton {
    min-height: 34px; padding: 0 14px; border-radius: 8px; border: 1px solid #cbd5e1;
    background: white; font-weight: 600;
}
QPushButton:hover { background: #f1f5f9; }
QPushButton:disabled { color: #94a3b8; background: #f8fafc; }
QPushButton#primaryButton { background: #0f766e; color: white; border: none; }
QPushButton#primaryButton:hover { background: #115e59; }
QPushButton#dangerButton { background: #dc2626; color: white; border: none; }
QLineEdit, QComboBox, QSpinBox, QTextEdit {
    background: white; border: 1px solid #cbd5e1; border-radius: 7px; padding: 7px;
}
QTableWidget, QTreeWidget {
    background: white; border: 1px solid #e2e8f0; border-radius: 9px; gridline-color: #edf2f7;
    alternate-background-color: #f8fafc;
}
QHeaderView::section { background: #f8fafc; padding: 7px; border: none; border-bottom: 1px solid #e2e8f0; font-weight: 700; }
"""


def _page_header(title: str, subtitle: str) -> QVBoxLayout:
    layout = QVBoxLayout()
    title_label = QLabel(title)
    title_label.setObjectName("pageTitle")
    subtitle_label = QLabel(subtitle)
    subtitle_label.setObjectName("pageSub")
    subtitle_label.setWordWrap(True)
    layout.addWidget(title_label)
    layout.addWidget(subtitle_label)
    return layout


def _button(text: str, name: str, *, primary: bool = False, danger: bool = False) -> QPushButton:
    button = QPushButton(text)
    button.setObjectName("primaryButton" if primary else "dangerButton" if danger else name)
    button.setAccessibleName(name)
    return button


class DashboardPage(QWidget):
    def __init__(self, controller: BaseController) -> None:
        super().__init__()
        self.controller = controller
        root = QVBoxLayout(self)
        root.setContentsMargins(24, 22, 24, 22)
        root.setSpacing(16)
        root.addLayout(_page_header("Research acquisition", "Connect both wheels, verify link health, then record. Raw samples stay inside the acquisition daemon."))

        actions = QHBoxLayout()
        self.scan_button = _button("Scan for wheels", "scanButton", primary=True)
        self.sync_button = _button("Sync clocks", "syncButton")
        self.refresh_button = _button("Refresh", "refreshButton")
        self.scan_button.clicked.connect(controller.scan)
        self.sync_button.clicked.connect(controller.sync_all)
        self.refresh_button.clicked.connect(controller.refresh_status)
        actions.addWidget(self.scan_button)
        actions.addWidget(self.sync_button)
        actions.addWidget(self.refresh_button)
        actions.addStretch(1)
        root.addLayout(actions)

        board_row = QHBoxLayout()
        self.board_cards = {"L": BoardSummaryCard("L"), "R": BoardSummaryCard("R")}
        board_row.addWidget(self.board_cards["L"])
        board_row.addWidget(self.board_cards["R"])
        root.addLayout(board_row)

        # Compact board configuration lives on the Dashboard so operators do
        # not need a separate settings page during a recording session.
        settings_card = Card()
        settings_layout = QHBoxLayout(settings_card)
        settings_layout.setContentsMargins(16, 12, 16, 12)
        settings_title = QLabel("Board settings")
        settings_title.setObjectName("cardTitle")
        settings_layout.addWidget(settings_title)
        settings_layout.addSpacing(10)
        settings_layout.addWidget(QLabel("Rate"))
        self.settings_rate = QComboBox()
        self.settings_rate.addItems(["50 Hz", "100 Hz", "200 Hz"])
        self.settings_rate.setCurrentText("100 Hz")
        self.settings_rate.setAccessibleName("boardRateSetting")
        settings_layout.addWidget(self.settings_rate)
        settings_layout.addWidget(QLabel("Accel"))
        self.settings_accel = QComboBox()
        self.settings_accel.addItems(["±2g", "±4g", "±8g", "±16g"])
        self.settings_accel.setCurrentIndex(1)
        self.settings_accel.setAccessibleName("boardAccelRangeSetting")
        settings_layout.addWidget(self.settings_accel)
        settings_layout.addWidget(QLabel("Gyro"))
        self.settings_gyro = QComboBox()
        self.settings_gyro.addItems(["±250°/s", "±500°/s", "±1000°/s", "±2000°/s"])
        self.settings_gyro.setCurrentIndex(3)
        self.settings_gyro.setAccessibleName("boardGyroRangeSetting")
        settings_layout.addWidget(self.settings_gyro)
        settings_layout.addStretch(1)
        self.apply_settings_l = _button("Apply L", "applySettingsLeft")
        self.apply_settings_r = _button("Apply R", "applySettingsRight")
        self.apply_settings_both = _button("Apply both", "applySettingsBoth", primary=True)
        settings_layout.addWidget(self.apply_settings_l)
        settings_layout.addWidget(self.apply_settings_r)
        settings_layout.addWidget(self.apply_settings_both)
        root.addWidget(settings_card)

        device_card = Card()
        device_layout = QVBoxLayout(device_card)
        device_layout.setContentsMargins(16, 14, 16, 16)
        heading = QHBoxLayout()
        title = QLabel("Nearby WheelAthlete devices")
        title.setObjectName("cardTitle")
        self.connect_button = _button("Connect selected", "connectSelectedButton", primary=True)
        self.disconnect_l = _button("Disconnect L", "disconnectLeftButton")
        self.disconnect_r = _button("Disconnect R", "disconnectRightButton")
        heading.addWidget(title)
        heading.addStretch(1)
        heading.addWidget(self.disconnect_l)
        heading.addWidget(self.disconnect_r)
        heading.addWidget(self.connect_button)
        device_layout.addLayout(heading)
        self.devices = QTableWidget(0, 3)
        self.devices.setHorizontalHeaderLabels(["Device", "RSSI", "ID"])
        self.devices.horizontalHeader().setSectionResizeMode(0, QHeaderView.ResizeMode.Stretch)
        self.devices.horizontalHeader().setSectionResizeMode(1, QHeaderView.ResizeMode.ResizeToContents)
        self.devices.horizontalHeader().setSectionResizeMode(2, QHeaderView.ResizeMode.Stretch)
        self.devices.setSelectionBehavior(QAbstractItemView.SelectionBehavior.SelectRows)
        self.devices.setSelectionMode(QAbstractItemView.SelectionMode.SingleSelection)
        self.devices.setAlternatingRowColors(True)
        self.devices.setAccessibleName("deviceTable")
        device_layout.addWidget(self.devices)
        root.addWidget(device_card, 1)

        self.connect_button.clicked.connect(self._connect_selected)
        self.disconnect_l.clicked.connect(lambda: controller.disconnect_side("L"))
        self.disconnect_r.clicked.connect(lambda: controller.disconnect_side("R"))
        self.apply_settings_l.clicked.connect(lambda: self._apply_settings(("L",)))
        self.apply_settings_r.clicked.connect(lambda: self._apply_settings(("R",)))
        self.apply_settings_both.clicked.connect(lambda: self._apply_settings(("L", "R")))
        controller.scan_results_changed.connect(self.update_devices)
        controller.state_changed.connect(self.update_state)
        self.update_state(controller.state)

    def _connect_selected(self) -> None:
        row = self.devices.currentRow()
        if row < 0:
            return
        item = self.devices.item(row, 2)
        if item is not None:
            self.controller.connect_device(item.text())

    def _apply_settings(self, sides: tuple[str, ...]) -> None:
        rate = int(self.settings_rate.currentText().split()[0])
        accel_range = self.settings_accel.currentIndex()
        gyro_range = self.settings_gyro.currentIndex()
        for side in sides:
            if self.controller.state.boards[side].connected:
                self.controller.configure_board(
                    side,
                    sample_rate_hz=rate,
                    accel_range=accel_range,
                    gyro_range=gyro_range,
                )

    def update_devices(self, devices: list[dict[str, Any]]) -> None:
        self.devices.setRowCount(len(devices))
        for row, device in enumerate(devices):
            self.devices.setItem(row, 0, QTableWidgetItem(str(device.get("name", "WheelAthlete"))))
            rssi = device.get("rssi")
            self.devices.setItem(row, 1, QTableWidgetItem("—" if rssi is None else f"{rssi} dBm"))
            self.devices.setItem(row, 2, QTableWidgetItem(str(device.get("device_id", ""))))

    def update_state(self, state: AppViewState) -> None:
        for side in ("L", "R"):
            self.board_cards[side].update_board(state.boards[side])
        self.sync_button.setEnabled(bool(state.connected_sides()))
        self.disconnect_l.setEnabled(state.boards["L"].connected and not state.recording)
        self.disconnect_r.setEnabled(state.boards["R"].connected and not state.recording)
        self.connect_button.setEnabled(not state.recording)
        self.scan_button.setEnabled(not state.recording)
        self.settings_rate.setEnabled(not state.recording)
        self.settings_accel.setEnabled(not state.recording)
        self.settings_gyro.setEnabled(not state.recording)
        self.apply_settings_l.setEnabled(state.boards["L"].connected and not state.recording)
        self.apply_settings_r.setEnabled(state.boards["R"].connected and not state.recording)
        self.apply_settings_both.setEnabled(bool(state.connected_sides()) and not state.recording)


class LivePage(QWidget):
    def __init__(self, controller: BaseController) -> None:
        super().__init__()
        self.controller = controller
        root = QVBoxLayout(self)
        root.setContentsMargins(24, 22, 24, 22)
        root.setSpacing(14)
        root.addLayout(_page_header("Realtime sensors", "All current sensor values are visible here. Charts use only the throttled preview; raw 50/100/200 Hz acquisition never enters the GUI process."))
        sensor_row = QHBoxLayout()
        self.current = {"L": CurrentSensorCard("L"), "R": CurrentSensorCard("R")}
        sensor_row.addWidget(self.current["L"])
        sensor_row.addWidget(self.current["R"])
        root.addLayout(sensor_row)

        charts = QHBoxLayout()
        self.accel_chart = MultiAxisChart("Acceleration — both wheels", "g", accel_value)
        self.gyro_chart = MultiAxisChart("Gyroscope — both wheels", "°/s", gyro_value)
        charts.addWidget(self.accel_chart, 1)
        charts.addWidget(self.gyro_chart, 1)
        root.addLayout(charts, 1)

        self._render = QTimer(self)
        self._render.setInterval(100)
        self._render.timeout.connect(self.render)
        self._render.start()
        controller.state_changed.connect(lambda _state: self.render_current())

    def render_current(self) -> None:
        for side in ("L", "R"):
            board = self.controller.state.boards[side]
            self.current[side].update_sample(
                self.controller.preview_buffer(side).latest(),
                accel_scale=board.accel_scale,
                gyro_scale=board.gyro_scale,
            )

    def render(self) -> None:
        self.render_current()
        self.accel_chart.update_from_controller(self.controller)
        self.gyro_chart.update_from_controller(self.controller)


class RecordPage(QWidget):
    def __init__(self, controller: BaseController) -> None:
        super().__init__()
        self.controller = controller
        root = QVBoxLayout(self)
        root.setContentsMargins(24, 22, 24, 22)
        root.setSpacing(16)
        root.addLayout(_page_header("Synchronized recording", "Configure metadata, then one button handles board configuration, clock sync, scheduled common start, raw journaling and final QC."))

        card = Card()
        card_layout = QVBoxLayout(card)
        card_layout.setContentsMargins(20, 18, 20, 20)
        form = QFormLayout()
        form.setHorizontalSpacing(18)
        self.athlete = QLineEdit()
        self.athlete.setAccessibleName("athleteInput")
        self.topic = QLineEdit()
        self.topic.setAccessibleName("topicInput")
        self.trial = QSpinBox()
        self.trial.setRange(1, 9999)
        self.trial.setAccessibleName("trialInput")
        self.rate = QComboBox()
        self.rate.addItems(["50", "100", "200"])
        self.rate.setCurrentText("100")
        self.rate.setAccessibleName("sampleRateInput")
        self.tags = QLineEdit()
        self.tags.setPlaceholderText("baseline, sprint, indoor")
        self.tags.setAccessibleName("tagsInput")
        self.notes = QTextEdit()
        self.notes.setMaximumHeight(110)
        self.notes.setAccessibleName("notesInput")
        form.addRow("Athlete", self.athlete)
        form.addRow("Topic", self.topic)
        form.addRow("Trial", self.trial)
        form.addRow("Sample rate", self.rate)
        form.addRow("Tags", self.tags)
        form.addRow("Notes", self.notes)
        card_layout.addLayout(form)

        actions = QHBoxLayout()
        self.start_button = _button("Start synchronized recording", "startRecordingButton", primary=True)
        self.stop_button = _button("Stop & validate", "stopRecordingButton", danger=True)
        self.stop_button.setVisible(False)
        actions.addWidget(self.start_button)
        actions.addWidget(self.stop_button)
        actions.addStretch(1)
        card_layout.addLayout(actions)
        root.addWidget(card)

        self.result = Card()
        result_layout = QVBoxLayout(self.result)
        self.result_title = QLabel("No finalized recording yet")
        self.result_title.setObjectName("cardTitle")
        self.result_detail = QLabel("Final QC compares host, firmware and authoritative journal counts.")
        self.result_detail.setWordWrap(True)
        self.result_detail.setObjectName("mutedText")
        result_layout.addWidget(self.result_title)
        result_layout.addWidget(self.result_detail)
        root.addWidget(self.result)
        root.addStretch(1)

        self.start_button.clicked.connect(self._start)
        self.stop_button.clicked.connect(controller.stop_record)
        controller.state_changed.connect(self.update_state)
        controller.recording_finished.connect(self._finished)
        self.update_state(controller.state)

    def metadata(self) -> dict[str, Any]:
        return {
            "athlete": self.athlete.text().strip(),
            "topic": self.topic.text().strip(),
            "trial_number": self.trial.value(),
            "sample_rate_hz": int(self.rate.currentText()),
            "notes": self.notes.toPlainText().strip(),
            "tags": [item.strip() for item in self.tags.text().split(",") if item.strip()],
        }

    def apply_template(self, template: ExperimentTemplate) -> None:
        self.athlete.setText(template.athlete)
        self.topic.setText(template.topic)
        self.rate.setCurrentText(str(template.sample_rate_hz))
        self.notes.setPlainText(template.notes)
        self.tags.setText(", ".join(template.tags))

    def _start(self) -> None:
        self.controller.start_record(self.metadata())

    def update_state(self, state: AppViewState) -> None:
        can_start = bool(state.connected_sides()) and state.daemon_connected and not state.recording
        self.start_button.setEnabled(can_start)
        self.start_button.setVisible(not state.recording)
        self.stop_button.setVisible(state.recording)
        self.stop_button.setEnabled(state.recording)
        for widget in (self.athlete, self.topic, self.trial, self.rate, self.tags, self.notes):
            widget.setEnabled(not state.recording)

    def _finished(self, result: dict[str, Any]) -> None:
        quality = str(result.get("quality", "UNKNOWN"))
        duration = result.get("duration_s")
        reasons = result.get("reasons", [])
        self.result_title.setText(f"Final QC: {quality}   •   {fmt(duration, ' s', 1)}")
        if reasons:
            text = "\n".join(
                f"• {item.get('code', 'check')}: {item.get('detail', '')}"
                for item in reasons
                if isinstance(item, dict)
            )
        else:
            text = "All recorded integrity checks passed." if quality == "GOOD" else "No additional QC reason was supplied."
        if result.get("demo"):
            text = "DEMO ONLY — synthetic preview was not written as research evidence."
        self.result_detail.setText(text)


class ExperimentsPage(QWidget):
    apply_template = Signal(object)

    def __init__(self, controller: BaseController) -> None:
        super().__init__()
        self.controller = controller
        self._templates: list[ExperimentTemplate] = []
        root = QVBoxLayout(self)
        root.setContentsMargins(24, 22, 24, 22)
        root.setSpacing(14)
        root.addLayout(_page_header("Experiments", "Save simple reusable recording presets. Applying a preset fills the Record page without changing the acquisition engine."))

        splitter = QHBoxLayout()
        left = Card()
        left_layout = QVBoxLayout(left)
        self.table = QTableWidget(0, 4)
        self.table.setHorizontalHeaderLabels(["Name", "Athlete", "Topic", "Rate"])
        self.table.horizontalHeader().setSectionResizeMode(0, QHeaderView.ResizeMode.Stretch)
        self.table.horizontalHeader().setSectionResizeMode(1, QHeaderView.ResizeMode.Stretch)
        self.table.horizontalHeader().setSectionResizeMode(2, QHeaderView.ResizeMode.Stretch)
        self.table.horizontalHeader().setSectionResizeMode(3, QHeaderView.ResizeMode.ResizeToContents)
        self.table.setSelectionBehavior(QAbstractItemView.SelectionBehavior.SelectRows)
        self.table.setSelectionMode(QAbstractItemView.SelectionMode.SingleSelection)
        left_layout.addWidget(self.table)
        row = QHBoxLayout()
        self.apply_button = _button("Use in Record", "applyExperimentButton", primary=True)
        self.delete_button = _button("Delete", "deleteExperimentButton")
        row.addWidget(self.apply_button)
        row.addWidget(self.delete_button)
        left_layout.addLayout(row)
        splitter.addWidget(left, 2)

        right = Card()
        right_layout = QVBoxLayout(right)
        title = QLabel("New preset")
        title.setObjectName("cardTitle")
        right_layout.addWidget(title)
        form = QFormLayout()
        self.name = QLineEdit()
        self.exp_athlete = QLineEdit()
        self.exp_topic = QLineEdit()
        self.exp_rate = QComboBox()
        self.exp_rate.addItems(["50", "100", "200"])
        self.exp_rate.setCurrentText("100")
        self.exp_tags = QLineEdit()
        self.exp_notes = QTextEdit()
        self.exp_notes.setMaximumHeight(100)
        form.addRow("Preset name", self.name)
        form.addRow("Athlete", self.exp_athlete)
        form.addRow("Topic", self.exp_topic)
        form.addRow("Rate", self.exp_rate)
        form.addRow("Tags", self.exp_tags)
        form.addRow("Notes", self.exp_notes)
        right_layout.addLayout(form)
        self.save_button = _button("Save preset", "saveExperimentButton", primary=True)
        right_layout.addWidget(self.save_button)
        right_layout.addStretch(1)
        splitter.addWidget(right, 1)
        root.addLayout(splitter, 1)

        self.save_button.clicked.connect(self._save)
        self.delete_button.clicked.connect(self._delete)
        self.apply_button.clicked.connect(self._apply)
        controller.experiments_changed.connect(self.update_templates)

    def update_templates(self, templates: list[ExperimentTemplate]) -> None:
        self._templates = list(templates)
        self.table.setRowCount(len(templates))
        for row, item in enumerate(templates):
            self.table.setItem(row, 0, QTableWidgetItem(item.name))
            self.table.setItem(row, 1, QTableWidgetItem(item.athlete))
            self.table.setItem(row, 2, QTableWidgetItem(item.topic))
            self.table.setItem(row, 3, QTableWidgetItem(f"{item.sample_rate_hz} Hz"))

    def _selected(self) -> ExperimentTemplate | None:
        row = self.table.currentRow()
        return self._templates[row] if 0 <= row < len(self._templates) else None

    def _save(self) -> None:
        name = self.name.text().strip()
        if not name:
            QMessageBox.warning(self, "Preset", "Enter a preset name first.")
            return
        template = ExperimentTemplate.new(
            name=name,
            athlete=self.exp_athlete.text(),
            topic=self.exp_topic.text(),
            sample_rate_hz=int(self.exp_rate.currentText()),
            notes=self.exp_notes.toPlainText(),
            tags=tuple(item.strip() for item in self.exp_tags.text().split(",") if item.strip()),
        )
        self.controller.save_experiment(template)
        self.name.clear()

    def _delete(self) -> None:
        selected = self._selected()
        if selected is not None:
            self.controller.delete_experiment(selected.id)

    def _apply(self) -> None:
        selected = self._selected()
        if selected is not None:
            self.apply_template.emit(selected)


class SessionsPage(QWidget):
    def __init__(self, controller: BaseController) -> None:
        super().__init__()
        self.controller = controller
        self._sessions: list[dict[str, Any]] = []
        self._visible: list[dict[str, Any]] = []
        root = QVBoxLayout(self)
        root.setContentsMargins(24, 22, 24, 22)
        root.setSpacing(14)
        root.addLayout(_page_header("Sessions", "Authoritative .waj sessions stay on disk. CSV is generated only when you explicitly export it."))
        toolbar = QHBoxLayout()
        self.search = QLineEdit()
        self.search.setPlaceholderText("Search athlete, topic, session ID…")
        self.search.setAccessibleName("sessionSearch")
        self.refresh = _button("Refresh", "refreshSessionsButton")
        self.export = _button("Export CSV", "exportSessionButton", primary=True)
        self.open_folder = _button("Open session folder", "openSessionFolderButton")
        toolbar.addWidget(self.search, 1)
        toolbar.addWidget(self.refresh)
        toolbar.addWidget(self.export)
        toolbar.addWidget(self.open_folder)
        root.addLayout(toolbar)
        self.table = QTableWidget(0, 8)
        self.table.setHorizontalHeaderLabels(["Quality", "Athlete", "Topic", "Trial", "Rate", "Duration", "L samples", "R samples"])
        self.table.horizontalHeader().setSectionResizeMode(1, QHeaderView.ResizeMode.Stretch)
        self.table.horizontalHeader().setSectionResizeMode(2, QHeaderView.ResizeMode.Stretch)
        for col in (0, 3, 4, 5, 6, 7):
            self.table.horizontalHeader().setSectionResizeMode(col, QHeaderView.ResizeMode.ResizeToContents)
        self.table.setSelectionBehavior(QAbstractItemView.SelectionBehavior.SelectRows)
        self.table.setSelectionMode(QAbstractItemView.SelectionMode.SingleSelection)
        self.table.setAlternatingRowColors(True)
        root.addWidget(self.table, 1)
        self.search.textChanged.connect(self._filter)
        self.refresh.clicked.connect(controller.refresh_sessions)
        self.export.clicked.connect(self._export)
        self.open_folder.clicked.connect(self._open_folder)
        controller.sessions_changed.connect(self.update_sessions)

    def update_sessions(self, sessions: list[dict[str, Any]]) -> None:
        self._sessions = list(sessions)
        self._filter()

    def _filter(self) -> None:
        query = self.search.text().strip().lower()
        self._visible = []
        for item in self._sessions:
            haystack = " ".join(str(item.get(key, "")) for key in ("session_id", "athlete", "topic", "quality")).lower()
            if not query or query in haystack:
                self._visible.append(item)
        self.table.setRowCount(len(self._visible))
        for row, item in enumerate(self._visible):
            counts = item.get("sample_counts") if isinstance(item.get("sample_counts"), dict) else {}
            values = [
                str(item.get("quality", "—")),
                str(item.get("athlete", "")),
                str(item.get("topic", "")),
                str(item.get("trial_number", "—")),
                f"{item.get('sample_rate_hz', '—')} Hz",
                fmt(item.get("duration_s"), " s", 1),
                f"{int(counts.get('L', 0) or 0):,}",
                f"{int(counts.get('R', 0) or 0):,}",
            ]
            for col, value in enumerate(values):
                self.table.setItem(row, col, QTableWidgetItem(value))

    def _selected(self) -> dict[str, Any] | None:
        row = self.table.currentRow()
        return self._visible[row] if 0 <= row < len(self._visible) else None

    def _export(self) -> None:
        selected = self._selected()
        if selected is None:
            return
        session_id = str(selected.get("session_id", ""))
        if not session_id:
            return
        output, _ = QFileDialog.getSaveFileName(self, "Export CSV", f"{session_id}.csv", "CSV files (*.csv)")
        if output:
            self.controller.export_session(session_id, output)

    def _open_folder(self) -> None:
        root = self.controller.state.journal_root
        if root:
            QDesktopServices.openUrl(QUrl.fromLocalFile(root))


class DiagnosticsPage(QWidget):
    def __init__(self, controller: BaseController) -> None:
        super().__init__()
        self.controller = controller
        root = QVBoxLayout(self)
        root.setContentsMargins(24, 22, 24, 22)
        root.setSpacing(14)
        root.addLayout(_page_header("Diagnostics", "One place for loss, queue, firmware, sync and UI-isolation metrics. RSSI alone is never treated as data quality."))
        toolbar = QHBoxLayout()
        self.refresh = _button("Refresh", "refreshDiagnosticsButton")
        self.export = _button("Export report", "exportDiagnosticsButton", primary=True)
        self.recover = _button("Recover incomplete journal", "recoverJournalButton")
        self.incomplete = QComboBox()
        self.incomplete.setAccessibleName("incompleteJournalCombo")
        toolbar.addWidget(self.refresh)
        toolbar.addWidget(self.export)
        toolbar.addStretch(1)
        toolbar.addWidget(self.incomplete)
        toolbar.addWidget(self.recover)
        root.addLayout(toolbar)

        self.tree = QTreeWidget()
        self.tree.setHeaderLabels(["Metric", "Left", "Right"])
        self.tree.header().setSectionResizeMode(0, QHeaderView.ResizeMode.Stretch)
        self.tree.header().setSectionResizeMode(1, QHeaderView.ResizeMode.ResizeToContents)
        self.tree.header().setSectionResizeMode(2, QHeaderView.ResizeMode.ResizeToContents)
        self.tree.setAlternatingRowColors(True)
        self.tree.setAccessibleName("diagnosticsTree")
        root.addWidget(self.tree, 1)

        self.ipc_card = Card()
        ipc_layout = QGridLayout(self.ipc_card)
        ipc_layout.setContentsMargins(16, 12, 16, 12)
        self.ipc_labels: dict[str, QLabel] = {}
        for col, (key, title) in enumerate([
            ("ready_clients", "UI clients"),
            ("preview_events_sent", "Preview sent"),
            ("preview_events_dropped", "Preview dropped"),
            ("max_preview_write_buffer_bytes", "Max IPC buffer"),
            ("preview_write_buffer_limit_bytes", "IPC buffer limit"),
        ]):
            box = QVBoxLayout()
            caption = QLabel(title)
            caption.setObjectName("metricLabel")
            value = QLabel("—")
            value.setObjectName("metricValue")
            self.ipc_labels[key] = value
            box.addWidget(caption)
            box.addWidget(value)
            ipc_layout.addLayout(box, 0, col)
        root.addWidget(self.ipc_card)
        self.refresh.clicked.connect(controller.refresh_status)
        self.export.clicked.connect(self._export)
        self.recover.clicked.connect(self._recover)
        controller.state_changed.connect(self.update_state)
        self.update_state(controller.state)

    def _export(self) -> None:
        output, _ = QFileDialog.getSaveFileName(self, "Export diagnostics", "wheelathlete-diagnostics.json", "JSON files (*.json)")
        if output:
            self.controller.export_diagnostics(output)

    def _recover(self) -> None:
        file_name = self.incomplete.currentText()
        if file_name:
            self.controller.recover_session(file_name)

    def update_state(self, state: AppViewState) -> None:
        self.tree.clear()
        metrics = [
            ("Link", lambda b: "Connected" if b.connected else "Offline"),
            ("RSSI", lambda b: fmt(b.rssi, " dBm", 0)),
            ("MTU", lambda b: fmt(b.mtu, "", 0)),
            ("Configured rate", lambda b: fmt(b.configured_rate_hz, " Hz", 0)),
            ("Accel range", lambda b: {0: "±2g", 1: "±4g", 2: "±8g", 3: "±16g"}.get(b.accel_range, "—")),
            ("Gyro range", lambda b: {0: "±250°/s", 1: "±500°/s", 2: "±1000°/s", 3: "±2000°/s"}.get(b.gyro_range, "—")),
            ("Effective samples/s", lambda b: fmt(b.samples_hz, " Hz", 2)),
            ("Notifications/s", lambda b: fmt(b.notifications_hz, " Hz", 2)),
            ("Host samples", lambda b: f"{b.samples:,}"),
            ("Host notifications", lambda b: f"{b.notifications:,}"),
            ("Sequence gaps", lambda b: str(b.sequence_gaps)),
            ("Duplicates", lambda b: str(b.duplicates)),
            ("Out of order", lambda b: str(b.out_of_order)),
            ("Malformed packets", lambda b: str(b.malformed_packets)),
            ("Host queue depth", lambda b: str(b.queue_depth)),
            ("Queue high-water", lambda b: str(b.queue_high_water)),
            ("Host queue overflow", lambda b: str(b.queue_overflow_faults)),
            ("FW produced", lambda b: fmt(b.produced, "", 0)),
            ("FW notified", lambda b: fmt(b.notified, "", 0)),
            ("FW queue drops", lambda b: fmt(b.firmware_queue_drops, "", 0)),
            ("Transport failures", lambda b: fmt(b.transport_failures, "", 0)),
            ("FW queue depth", lambda b: fmt(b.firmware_queue_depth, "", 0)),
            ("FIFO faults", lambda b: fmt(b.fifo_faults, "", 0)),
            ("FIFO samples lost", lambda b: fmt(b.fifo_dropped_samples, "", 0)),
            ("Best sync RTT", lambda b: fmt(b.best_rtt_ms, " ms", 2)),
            ("Median sync RTT", lambda b: fmt(b.median_rtt_ms, " ms", 2)),
            ("Clock drift", lambda b: fmt(b.drift_ppm, " ppm", 2)),
            ("Clock residual", lambda b: fmt(b.residual_rms_ms, " ms", 3)),
        ]
        for name, getter in metrics:
            self.tree.addTopLevelItem(QTreeWidgetItem([name, getter(state.boards["L"]), getter(state.boards["R"])]))
        self.tree.expandAll()
        current = self.incomplete.currentText()
        self.incomplete.blockSignals(True)
        self.incomplete.clear()
        self.incomplete.addItems(list(state.incomplete_sessions))
        if current:
            index = self.incomplete.findText(current)
            if index >= 0:
                self.incomplete.setCurrentIndex(index)
        self.incomplete.blockSignals(False)
        self.recover.setEnabled(bool(state.incomplete_sessions))
        for key, label in self.ipc_labels.items():
            value = state.ipc.get(key)
            if key.endswith("bytes") and isinstance(value, (int, float)):
                label.setText(f"{float(value) / 1024:.1f} KiB")
            else:
                label.setText("—" if value is None else str(value))


class MainWindow(QMainWindow):
    def __init__(self, controller: BaseController, *, demo: bool = False) -> None:
        super().__init__()
        self.controller = controller
        self.demo = demo
        self.setWindowTitle("WheelAthlete — Python Research Edition")
        self.resize(1500, 930)
        self.setMinimumSize(1180, 760)
        self.setStyleSheet(APP_QSS)
        self.setAccessibleName("WheelAthletePythonResearchEdition")

        root = QWidget()
        root.setObjectName("root")
        self.setCentralWidget(root)
        layout = QHBoxLayout(root)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(0)

        sidebar = QFrame()
        sidebar.setObjectName("sidebar")
        sidebar.setFixedWidth(205)
        side_layout = QVBoxLayout(sidebar)
        side_layout.setContentsMargins(14, 22, 14, 18)
        brand = QLabel("WheelAthlete")
        brand.setObjectName("brand")
        sub = QLabel("PYTHON RESEARCH EDITION")
        sub.setObjectName("brandSub")
        side_layout.addWidget(brand)
        side_layout.addWidget(sub)
        side_layout.addSpacing(18)
        self.nav = QListWidget()
        self.nav.setObjectName("nav")
        self.nav.setAccessibleName("mainNavigation")
        for title, subtitle in NAV_ITEMS:
            item = QListWidgetItem(f"{title}\n{subtitle}")
            item.setSizeHint(item.sizeHint().expandedTo(item.sizeHint()))
            self.nav.addItem(item)
        self.nav.setCurrentRow(0)
        side_layout.addWidget(self.nav, 1)
        if demo:
            demo_badge = QLabel("DEMO DATA")
            demo_badge.setObjectName("demoBadge")
            demo_badge.setAlignment(Qt.AlignmentFlag.AlignCenter)
            side_layout.addWidget(demo_badge)
        layout.addWidget(sidebar)

        content = QWidget()
        content_layout = QVBoxLayout(content)
        content_layout.setContentsMargins(0, 0, 0, 0)
        content_layout.setSpacing(0)
        header = QFrame()
        header.setStyleSheet("QFrame { background: white; border-bottom: 1px solid #e2e8f0; }")
        header_layout = QHBoxLayout(header)
        header_layout.setContentsMargins(22, 10, 22, 10)
        self.daemon_badge = QLabel("Daemon offline")
        self.daemon_badge.setObjectName("daemonBadge")
        self.record_badge = QLabel("IDLE")
        self.record_badge.setObjectName("recordBadge")
        self.session_label = QLabel("")
        self.session_label.setObjectName("mutedText")
        header_layout.addWidget(self.daemon_badge)
        header_layout.addWidget(self.record_badge)
        header_layout.addWidget(self.session_label)
        header_layout.addStretch(1)
        content_layout.addWidget(header)

        self.stack = QStackedWidget()
        self.dashboard = DashboardPage(controller)
        self.live = LivePage(controller)
        self.record = RecordPage(controller)
        self.experiments = ExperimentsPage(controller)
        self.sessions = SessionsPage(controller)
        self.diagnostics = DiagnosticsPage(controller)
        for page in (self.dashboard, self.live, self.record, self.experiments, self.sessions, self.diagnostics):
            self.stack.addWidget(page)
        content_layout.addWidget(self.stack, 1)
        layout.addWidget(content, 1)

        self.nav.currentRowChanged.connect(self.stack.setCurrentIndex)
        self.experiments.apply_template.connect(self._apply_template)
        controller.state_changed.connect(self._update_header)
        controller.message.connect(self._show_message)
        controller.command_error.connect(self._show_error)
        controller.sessions_changed.connect(self.sessions.update_sessions)
        self._update_header(controller.state)

        toggle_action = QAction("Toggle fullscreen", self)
        toggle_action.setShortcut("F11")
        toggle_action.triggered.connect(lambda: self.showNormal() if self.isFullScreen() else self.showFullScreen())
        self.addAction(toggle_action)

    def start(self) -> None:
        self.controller.start()

    def _apply_template(self, template: ExperimentTemplate) -> None:
        self.record.apply_template(template)
        self.nav.setCurrentRow(2)
        self._show_message(f"Preset applied: {template.name}")

    def _update_header(self, state: AppViewState) -> None:
        self.daemon_badge.setText("DAQ READY" if state.daemon_connected else "Daemon offline")
        self.daemon_badge.setProperty("online", state.daemon_connected)
        self.daemon_badge.style().unpolish(self.daemon_badge)
        self.daemon_badge.style().polish(self.daemon_badge)
        self.record_badge.setText("RECORDING" if state.recording else "IDLE")
        self.record_badge.setProperty("recording", state.recording)
        self.record_badge.style().unpolish(self.record_badge)
        self.record_badge.style().polish(self.record_badge)
        self.session_label.setText(f"Session {state.session_id}" if state.session_id else "")

    def _show_message(self, text: str) -> None:
        self.statusBar().showMessage(text, 5000)

    def _show_error(self, command: str, message: str) -> None:
        self.statusBar().showMessage(f"{command}: {message}", 8000)

    def closeEvent(self, event: QCloseEvent) -> None:
        if self.controller.state.recording and not self.demo:
            answer = QMessageBox.question(
                self,
                "Recording is still active",
                "Close only the UI and leave the acquisition daemon recording?\n\nRaw data will continue to be owned by the daemon.",
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.Cancel,
                QMessageBox.StandardButton.Cancel,
            )
            if answer != QMessageBox.StandardButton.Yes:
                event.ignore()
                return
        self.controller.close()
        event.accept()
