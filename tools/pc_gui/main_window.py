from __future__ import annotations

import csv
import json
import os
import winsound
from pathlib import Path
from threading import Thread
from typing import Any

from PySide6.QtCore import (
    QAbstractItemModel,
    QEvent,
    QLocale,
    QModelIndex,
    QPointF,
    QRectF,
    QTimer,
    QUrl,
    Qt,
    Signal,
)
from PySide6.QtGui import (
    QAction,
    QBrush,
    QCloseEvent,
    QColor,
    QDesktopServices,
    QFont,
    QPainter,
    QPen,
)
from PySide6.QtCharts import QChart, QChartView, QLineSeries, QScatterSeries, QValueAxis
from PySide6.QtWidgets import (
    QAbstractItemView,
    QApplication,
    QCheckBox,
    QComboBox,
    QDialog,
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
    QScrollArea,
    QSizePolicy,
    QSpinBox,
    QSplitter,
    QStackedWidget,
    QStyle,
    QStyledItemDelegate,
    QStyleOptionViewItem,
    QTabWidget,
    QTableWidget,
    QTableWidgetItem,
    QTextEdit,
    QTreeWidget,
    QTreeWidgetItem,
    QVBoxLayout,
    QWidget,
)

from .controller import BaseController, sanitize_name
from .state import AppViewState
from .widgets import (
    BoardSummaryCard,
    Card,
    CurrentSensorCard,
    MultiAxisChart,
    accel_value,
    fmt,
    gyro_value,
    style_chart_surface,
)


NAV_ITEMS = [
    ("Dashboard", "Overview & connect"),
    ("Acquisition", "Live preview & record"),
    ("Results", "Sessions & CSV export"),
    ("Diagnostics", "Data integrity"),
]


class CheckBoxDelegate(QStyledItemDelegate):
    """Paints crisp, high-contrast checkmark boxes on any table cell."""

    def __init__(self, table: QTableWidget | None = None) -> None:
        super().__init__(table)
        self.table = table

    def paint(self, painter: QPainter, option: QStyleOptionViewItem, index: QModelIndex) -> None:
        bg = index.data(Qt.ItemDataRole.BackgroundRole)
        if bg is not None:
            painter.fillRect(option.rect, bg)
        elif option.state & QStyle.StateFlag.State_Selected:
            painter.fillRect(option.rect, QColor("#0f766e"))

        value = index.data(Qt.ItemDataRole.CheckStateRole)
        if value is None:
            super().paint(painter, option, index)
            return

        painter.save()
        painter.setRenderHint(QPainter.RenderHint.Antialiasing, True)

        box_size = 18
        x = option.rect.x() + (option.rect.width() - box_size) // 2
        y = option.rect.y() + (option.rect.height() - box_size) // 2
        rect = QRectF(x, y, box_size, box_size)

        is_checked = (value == Qt.CheckState.Checked or value == Qt.CheckState.Checked.value or value == 2)
        is_hovered = bool(option.state & QStyle.StateFlag.State_MouseOver)

        if is_checked:
            painter.setBrush(QColor("#0f766e"))
            painter.setPen(QPen(QColor("#0f766e"), 1.5))
            painter.drawRoundedRect(rect, 4, 4)

            pen = QPen(QColor("#ffffff"), 2.2, Qt.PenStyle.SolidLine, Qt.PenCapStyle.RoundCap, Qt.PenJoinStyle.RoundJoin)
            painter.setPen(pen)
            painter.drawLine(QPointF(x + 4.5, y + 9.5), QPointF(x + 7.5, y + 13.0))
            painter.drawLine(QPointF(x + 7.5, y + 13.0), QPointF(x + 13.5, y + 5.0))
        else:
            border_color = QColor("#0f766e") if is_hovered else QColor("#94a3b8")
            bg_color = QColor("#f0fdfa") if is_hovered else QColor("#ffffff")
            painter.setBrush(bg_color)
            painter.setPen(QPen(border_color, 1.8))
            painter.drawRoundedRect(rect, 4, 4)

        painter.restore()

    def editorEvent(self, event: QEvent, model: QAbstractItemModel, option: QStyleOptionViewItem, index: QModelIndex) -> bool:
        if event.type() in (QEvent.Type.MouseButtonRelease, QEvent.Type.MouseButtonDblClick):
            if self.table is not None:
                item = self.table.item(index.row(), index.column())
                if item is not None:
                    current_checked = (
                        item.checkState() in (Qt.CheckState.Checked, Qt.CheckState.Checked.value, 2)
                        or item.data(Qt.ItemDataRole.CheckStateRole) in (Qt.CheckState.Checked, Qt.CheckState.Checked.value, 2)
                    )
                    new_state = Qt.CheckState.Unchecked if current_checked else Qt.CheckState.Checked
                    item.setCheckState(new_state)
                    return True
            current = index.data(Qt.ItemDataRole.CheckStateRole)
            if current is not None:
                is_checked = (current in (Qt.CheckState.Checked, Qt.CheckState.Checked.value, 2))
                new_state = Qt.CheckState.Unchecked if is_checked else Qt.CheckState.Checked
                model.setData(index, new_state, Qt.ItemDataRole.CheckStateRole)
                return True
        return super().editorEvent(event, model, option, index)


APP_QSS = """
QWidget {
    font-family: "Segoe UI", system-ui, sans-serif;
    font-size: 13px;
    color: #172033;
}
QMainWindow, QWidget#root, QWidget#pageContent, QScrollArea, QScrollArea > QWidget, QWidget#topicContainer {
    background-color: #f5f7fb;
}
QFrame#sidebar { background-color: #111827; border: none; }
QLabel#brand { color: white; font-size: 22px; font-weight: 700; }
QLabel#brandSub { color: #94a3b8; font-size: 11px; }
QListWidget#nav {
    background: transparent; border: none; color: #cbd5e1; outline: none;
}
QListWidget#nav::item { padding: 12px 14px; margin: 2px 7px; border-radius: 8px; }
QListWidget#nav::item:selected { background: #0f766e; color: white; }
QListWidget#nav::item:hover:!selected { background: #1f2937; }
QFrame#card { background-color: white; border: 1px solid #e2e8f0; border-radius: 12px; }
QLabel#pageTitle { font-size: 24px; font-weight: 700; }
QLabel#pageSub { color: #64748b; }
QLabel#cardTitle { font-size: 16px; font-weight: 700; }
QLabel#mutedText, QLabel#metricLabel { color: #64748b; }
QLabel#metricLabel { font-size: 11px; }
QLabel#metricValue { font-size: 17px; font-weight: 700; }
QLabel#statusPill {
    padding: 4px 9px; border-radius: 9px; font-size: 10px; font-weight: 700;
    background-color: #e2e8f0; color: #475569;
}
QLabel#statusPill[state="good"] { background-color: #dcfce7; color: #166534; }
QLabel#statusPill[state="warning"] { background-color: #fef3c7; color: #92400e; }
QLabel#statusPill[state="offline"] { background-color: #e2e8f0; color: #475569; }
QLabel#daemonBadge { padding: 6px 10px; border-radius: 10px; background-color: #fee2e2; color: #991b1b; font-weight: 600; }
QLabel#daemonBadge[online="true"] { background-color: #dcfce7; color: #166534; }
QLabel#recordBadge { padding: 6px 10px; border-radius: 10px; background-color: #e2e8f0; color: #475569; font-weight: 700; }
QLabel#recordBadge[recording="true"] { background-color: #fee2e2; color: #b91c1c; }
QLabel#recordBadge[live="true"] { background-color: #dbeafe; color: #1d4ed8; }
QLabel#demoBadge { padding: 6px 10px; border-radius: 10px; background-color: #fef3c7; color: #92400e; font-weight: 800; }
QPushButton {
    min-height: 34px; padding: 0 14px; border-radius: 8px; border: 1px solid #cbd5e1;
    background-color: white; font-weight: 600;
}
QPushButton:hover { background-color: #f1f5f9; }
QPushButton:disabled { color: #94a3b8; background-color: #f8fafc; }
QPushButton#primaryButton { background-color: #0f766e; color: white; border: none; }
QPushButton#primaryButton:hover { background-color: #115e59; }
QPushButton#dangerButton { background-color: #dc2626; color: white; border: none; }
QLineEdit, QComboBox, QSpinBox, QTextEdit {
    background-color: white; border: 1px solid #cbd5e1; border-radius: 7px; padding: 7px;
}
QComboBox QAbstractItemView {
    background-color: white; color: #172033; border: 1px solid #cbd5e1;
    selection-background-color: #0f766e; selection-color: white; outline: none;
}
QCheckBox {
    spacing: 8px;
    font-weight: 600;
}
QCheckBox::indicator {
    width: 18px;
    height: 18px;
    border: 2px solid #94a3b8;
    border-radius: 4px;
    background-color: #ffffff;
}
QCheckBox::indicator:hover {
    border-color: #0f766e;
    background-color: #f0fdfa;
}
QCheckBox::indicator:checked {
    background-color: #0f766e;
    border-color: #0f766e;
}
QTableWidget, QTreeWidget {
    background-color: #ffffff; border: 1px solid #e2e8f0; border-radius: 9px; gridline-color: #edf2f7;
    alternate-background-color: #f8fafc; selection-background-color: #0f766e;
    selection-color: white;
}
QTableWidget::item { color: #172033; background-color: #ffffff; padding: 5px; }
QTableWidget::item:alternate { background-color: #f8fafc; }
QTableWidget::item:selected { background-color: #0f766e; color: white; }
QHeaderView::section { background-color: #f8fafc; color: #172033; padding: 7px; border: none; border-bottom: 1px solid #e2e8f0; font-weight: 700; }
QTableCornerButton::section { background-color: #f8fafc; border: none; border-bottom: 1px solid #e2e8f0; }
QTabWidget {
    background-color: #f5f7fb;
}
QTabWidget::pane {
    background-color: #f5f7fb;
    border: none;
    margin-top: 10px;
}
QTabBar {
    background-color: #f5f7fb;
}
QTabBar::tab {
    background-color: #e2e8f0;
    color: #334155;
    padding: 8px 18px;
    margin-right: 6px;
    border-radius: 8px;
    font-weight: 600;
}
QTabBar::tab:selected {
    background-color: #0f766e;
    color: #ffffff;
}
QTabBar::tab:hover:!selected {
    background-color: #cbd5e1;
}
QScrollArea {
    background-color: #f5f7fb;
    border: none;
}
QScrollArea > QWidget > QWidget {
    background-color: #f5f7fb;
}
QFrame#topicCard {
    background-color: #ffffff;
    border: 1px solid #cbd5e1;
    border-radius: 12px;
}
QFrame#topicCard[expanded="true"] {
    border: 1.5px solid #0f766e;
    background-color: #ffffff;
}
QLabel#topicTitle {
    font-size: 16px;
    font-weight: 700;
    color: #0f766e;
}
QLabel#topicCountPill {
    background-color: #e0f2fe;
    color: #0369a1;
    padding: 3px 9px;
    border-radius: 6px;
    font-size: 11px;
    font-weight: 700;
}
QLabel#topicAthletesPill {
    background-color: #f1f5f9;
    color: #334155;
    padding: 2px 7px;
    border-radius: 6px;
    font-size: 10px;
    font-weight: 500;
}
QPushButton#seeMoreButton {
    min-height: 28px;
    padding: 0 14px;
    border-radius: 6px;
    border: 1px solid #0f766e;
    color: #0f766e;
    background-color: #f0fdfa;
    font-size: 12px;
    font-weight: 600;
}
QPushButton#seeMoreButton:hover {
    background-color: #0f766e;
    color: #ffffff;
}
QPushButton#previewTableBtn {
    min-height: 24px;
    max-height: 26px;
    min-width: 82px;
    max-width: 82px;
    padding: 0 8px;
    border-radius: 6px;
    border: 1px solid #0f766e;
    color: #0f766e;
    background-color: #f0fdfa;
    font-size: 11px;
    font-weight: 700;
}
QPushButton#previewTableBtn:hover {
    background-color: #0f766e;
    color: #ffffff;
}
QPushButton#previewTableBtn[active="true"] {
    background-color: #0f766e;
    color: #ffffff;
    border-color: #0f766e;
}
QFrame#previewCard {
    background-color: #ffffff;
    border: 1.5px solid #0f766e;
    border-radius: 12px;
}
QLabel#previewLossGood {
    background-color: #dcfce7;
    color: #166534;
    padding: 6px 12px;
    border-radius: 8px;
    font-weight: 700;
    font-size: 12px;
}
QLabel#previewLossWarn {
    background-color: #fee2e2;
    color: #991b1b;
    padding: 6px 12px;
    border-radius: 8px;
    font-weight: 700;
    font-size: 12px;
}
QDialog, QMessageBox {
    background-color: #ffffff;
    color: #1e293b;
    font-family: "Segoe UI", system-ui, sans-serif;
    font-size: 13px;
}
QMessageBox QLabel {
    color: #1e293b;
    font-size: 13px;
    font-weight: 500;
}
QMessageBox QPushButton {
    min-width: 85px;
    min-height: 32px;
    padding: 0 16px;
    border-radius: 6px;
    background-color: #0f766e;
    color: #ffffff;
    font-weight: 600;
    border: none;
}
QMessageBox QPushButton:hover {
    background-color: #115e59;
}
QMessageBox QPushButton:pressed {
    background-color: #042f2e;
}
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


def _table_action_button(text: str, name: str, callback, *, active: bool = False) -> QWidget:
    container = QWidget()
    container.setStyleSheet("background: transparent;")
    layout = QHBoxLayout(container)
    layout.setContentsMargins(0, 2, 0, 2)
    layout.setSpacing(0)
    layout.setAlignment(Qt.AlignmentFlag.AlignCenter)
    btn = QPushButton(text)
    btn.setObjectName(name)
    btn.setCursor(Qt.CursorShape.PointingHandCursor)
    btn.setFixedHeight(26)
    btn.setFixedWidth(82)
    if active:
        btn.setProperty("active", "true")
    btn.clicked.connect(callback)
    layout.addWidget(btn)
    return container


def _play_tone(frequency: int, duration_ms: int) -> None:
    def play() -> None:
        try:
            winsound.Beep(frequency, duration_ms)
        except RuntimeError:
            winsound.MessageBeep()

    Thread(target=play, daemon=True).start()


class ModernDialog(QDialog):
    """Clean, beautifully padded modal dialog that prevents text clipping and Windows scaling issues."""

    def __init__(
        self,
        title: str,
        message: str,
        icon_type: str = "question",
        buttons: list[tuple[str, str, bool]] | None = None,
        parent: QWidget | None = None,
    ) -> None:
        super().__init__(parent)
        self.setWindowTitle(title)
        self.setModal(True)
        self.setMinimumWidth(440)
        self.setStyleSheet("""
            QDialog {
                background-color: #ffffff;
                border: 1px solid #cbd5e1;
                border-radius: 10px;
                font-family: "Segoe UI", system-ui, sans-serif;
            }
        """)

        layout = QVBoxLayout(self)
        layout.setContentsMargins(24, 22, 24, 20)
        layout.setSpacing(18)

        body_layout = QHBoxLayout()
        body_layout.setSpacing(16)
        body_layout.setAlignment(Qt.AlignmentFlag.AlignTop)

        icon_label = QLabel()
        icon_label.setFixedSize(38, 38)
        icon_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        if icon_type == "danger":
            icon_label.setText("!")
            icon_label.setStyleSheet("background-color: #fee2e2; color: #dc2626; border-radius: 19px; font-weight: bold; font-size: 18px;")
        elif icon_type == "warning":
            icon_label.setText("!")
            icon_label.setStyleSheet("background-color: #fef3c7; color: #d97706; border-radius: 19px; font-weight: bold; font-size: 18px;")
        elif icon_type == "question":
            icon_label.setText("?")
            icon_label.setStyleSheet("background-color: #e0f2fe; color: #0284c7; border-radius: 19px; font-weight: bold; font-size: 18px;")
        else:
            icon_label.setText("i")
            icon_label.setStyleSheet("background-color: #f0fdfa; color: #0f766e; border-radius: 19px; font-weight: bold; font-size: 18px;")

        body_layout.addWidget(icon_label, 0, Qt.AlignmentFlag.AlignTop)

        text_layout = QVBoxLayout()
        text_layout.setSpacing(6)

        parts = message.split("\n\n", 1)
        msg_title = QLabel(parts[0])
        msg_title.setWordWrap(True)
        msg_title.setStyleSheet("color: #0f172a; font-size: 14px; font-weight: 600; line-height: 1.4;")
        text_layout.addWidget(msg_title)

        if len(parts) > 1:
            msg_desc = QLabel(parts[1])
            msg_desc.setWordWrap(True)
            msg_desc.setStyleSheet("color: #64748b; font-size: 13px; line-height: 1.4;")
            text_layout.addWidget(msg_desc)

        body_layout.addLayout(text_layout, 1)
        layout.addLayout(body_layout)

        btn_layout = QHBoxLayout()
        btn_layout.setSpacing(10)
        btn_layout.addStretch(1)

        if buttons:
            for btn_text, btn_role, is_danger in buttons:
                b = QPushButton(btn_text)
                b.setFixedHeight(34)
                b.setMinimumWidth(90)
                b.setCursor(Qt.CursorShape.PointingHandCursor)
                if btn_role == "accept":
                    if is_danger:
                        b.setStyleSheet("QPushButton { background-color: #dc2626; color: #ffffff; border: none; border-radius: 6px; font-weight: 600; padding: 0 16px; font-size: 13px; } QPushButton:hover { background-color: #b91c1c; }")
                    else:
                        b.setStyleSheet("QPushButton { background-color: #0f766e; color: #ffffff; border: none; border-radius: 6px; font-weight: 600; padding: 0 16px; font-size: 13px; } QPushButton:hover { background-color: #115e59; }")
                    b.clicked.connect(self.accept)
                else:
                    b.setStyleSheet("QPushButton { background-color: #ffffff; color: #475569; border: 1px solid #cbd5e1; border-radius: 6px; font-weight: 600; padding: 0 16px; font-size: 13px; } QPushButton:hover { background-color: #f1f5f9; color: #1e293b; }")
                    b.clicked.connect(self.reject)
                btn_layout.addWidget(b)
        else:
            ok_btn = QPushButton("OK")
            ok_btn.setFixedHeight(34)
            ok_btn.setMinimumWidth(90)
            ok_btn.setCursor(Qt.CursorShape.PointingHandCursor)
            ok_btn.setStyleSheet("QPushButton { background-color: #0f766e; color: #ffffff; border: none; border-radius: 6px; font-weight: 600; padding: 0 16px; font-size: 13px; } QPushButton:hover { background-color: #115e59; }")
            ok_btn.clicked.connect(self.accept)
            btn_layout.addWidget(ok_btn)

        layout.addLayout(btn_layout)


def _show_info_dialog(parent: QWidget | None, title: str, message: str) -> None:
    dlg = ModernDialog(title, message, icon_type="info", parent=parent)
    dlg.exec()


def _ask_confirm_dialog(
    parent: QWidget | None,
    title: str,
    message: str,
    confirm_text: str = "Yes",
    cancel_text: str = "Cancel",
    danger: bool = False,
) -> bool:
    buttons = [
        (cancel_text, "reject", False),
        (confirm_text, "accept", danger),
    ]
    dlg = ModernDialog(title, message, icon_type="danger" if danger else "question", buttons=buttons, parent=parent)
    return dlg.exec() == QDialog.DialogCode.Accepted


class DashboardPage(QWidget):
    def __init__(self, controller: BaseController) -> None:
        super().__init__()
        self.controller = controller
        root = QVBoxLayout(self)
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
        self.connect_button = _button("Connect both wheels", "connectBothButton", primary=True)
        self.disconnect_l = _button("Disconnect L", "disconnectLeftButton")
        self.disconnect_r = _button("Disconnect R", "disconnectRightButton")
        heading.addWidget(title)
        heading.addStretch(1)
        heading.addWidget(self.disconnect_l)
        heading.addWidget(self.disconnect_r)
        heading.addWidget(self.connect_button)
        device_layout.addLayout(heading)
        self.action_status = QLabel("Scan, then connect both wheels. Double-click a row to connect only that device.")
        self.action_status.setObjectName("mutedText")
        self.action_status.setAccessibleName("connectionStatus")
        device_layout.addWidget(self.action_status)
        self.devices = QTableWidget(0, 4)
        self.devices.setHorizontalHeaderLabels(["Device", "Status", "RSSI", "ID"])
        self.devices.horizontalHeader().setSectionResizeMode(0, QHeaderView.ResizeMode.Stretch)
        self.devices.horizontalHeader().setSectionResizeMode(1, QHeaderView.ResizeMode.ResizeToContents)
        self.devices.horizontalHeader().setSectionResizeMode(2, QHeaderView.ResizeMode.ResizeToContents)
        self.devices.horizontalHeader().setSectionResizeMode(3, QHeaderView.ResizeMode.Stretch)
        self.devices.verticalHeader().hide()
        self.devices.setEditTriggers(QAbstractItemView.EditTrigger.NoEditTriggers)
        self.devices.setSelectionBehavior(QAbstractItemView.SelectionBehavior.SelectRows)
        self.devices.setSelectionMode(QAbstractItemView.SelectionMode.SingleSelection)
        self.devices.setAlternatingRowColors(True)
        self.devices.setAccessibleName("deviceTable")
        device_layout.addWidget(self.devices)
        root.addWidget(device_card, 1)

        self.connect_button.clicked.connect(self._connect_all)
        self.devices.cellDoubleClicked.connect(self._connect_row)
        self.disconnect_l.clicked.connect(lambda: controller.disconnect_side("L"))
        self.disconnect_r.clicked.connect(lambda: controller.disconnect_side("R"))
        self.apply_settings_l.clicked.connect(lambda: self._apply_settings(("L",)))
        self.apply_settings_r.clicked.connect(lambda: self._apply_settings(("R",)))
        self.apply_settings_both.clicked.connect(lambda: self._apply_settings(("L", "R")))
        controller.scan_results_changed.connect(self.update_devices)
        controller.state_changed.connect(self.update_state)
        controller.message.connect(self.action_status.setText)
        controller.command_error.connect(
            lambda command, message: self.action_status.setText(f"{command}: {message}")
        )
        self.update_state(controller.state)

    def _connect_all(self) -> None:
        device_ids = [
            item.text()
            for row in range(self.devices.rowCount())
            if (item := self.devices.item(row, 3)) is not None and item.text()
        ]
        if not device_ids:
            self.action_status.setText("No devices listed. Scan for wheels first.")
            return
        self.controller.connect_devices(device_ids)

    def _connect_row(self, row: int, _column: int) -> None:
        item = self.devices.item(row, 3)
        if item is not None and item.text():
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
            self.devices.setItem(row, 1, QTableWidgetItem("Available"))
            rssi = device.get("rssi")
            self.devices.setItem(row, 2, QTableWidgetItem("—" if rssi is None else f"{rssi} dBm"))
            self.devices.setItem(row, 3, QTableWidgetItem(str(device.get("device_id", ""))))
        if devices:
            self.devices.selectRow(0)
        self._update_device_status()

    def _update_device_status(self) -> None:
        connected = {
            board.device_id: side
            for side, board in self.controller.state.boards.items()
            if board.connected and board.device_id
        }
        for row in range(self.devices.rowCount()):
            device_id = self.devices.item(row, 3)
            status = self.devices.item(row, 1)
            if device_id is not None and status is not None:
                side = connected.get(device_id.text())
                status.setText(f"Connected {side}" if side else "Available")

    def update_state(self, state: AppViewState) -> None:
        for side in ("L", "R"):
            self.board_cards[side].update_board(
                state.boards[side], active=state.live or state.recording
            )
        busy = state.scanning or state.connecting or state.live_busy or state.recording_starting
        idle = not state.recording and not state.live and not busy
        self.sync_button.setEnabled(bool(state.connected_sides()) and idle)
        self.disconnect_l.setEnabled(state.boards["L"].connected and idle)
        self.disconnect_r.setEnabled(state.boards["R"].connected and idle)
        self.connect_button.setEnabled(bool(self.controller.scan_results) and idle)
        self.connect_button.setText("Connecting…" if state.connecting else "Connect both wheels")
        self.scan_button.setEnabled(state.daemon_connected and idle)
        self.scan_button.setText("Scanning…" if state.scanning else "Scan for wheels")
        self.settings_rate.setEnabled(idle)
        self.settings_accel.setEnabled(idle)
        self.settings_gyro.setEnabled(idle)
        self.apply_settings_l.setEnabled(state.boards["L"].connected and idle)
        self.apply_settings_r.setEnabled(state.boards["R"].connected and idle)
        self.apply_settings_both.setEnabled(bool(state.connected_sides()) and idle)
        self._update_device_status()




class AcquisitionPage(QWidget):
    """Unified single screen for Live IMU preview and Synchronized Recording."""

    def __init__(self, controller: BaseController) -> None:
        super().__init__()
        self.controller = controller
        root = QVBoxLayout(self)
        root.setContentsMargins(24, 20, 24, 20)
        root.setSpacing(14)
        root.addLayout(
            _page_header(
                "Live preview & synchronized recording",
                "Monitor real-time IMU telemetry, edit recording parameters, and capture synchronized dual-wheel research data.",
            )
        )

        main_layout = QHBoxLayout()
        main_layout.setSpacing(16)

        # LEFT COLUMN: Controls & Metadata Configuration (Width ~400px)
        left_col = QVBoxLayout()
        left_col.setSpacing(12)

        # Live Preview Toggle Card
        live_card = Card()
        live_layout = QVBoxLayout(live_card)
        live_layout.setContentsMargins(16, 14, 16, 14)
        live_layout.setSpacing(8)
        live_header = QHBoxLayout()
        live_title = QLabel("Live preview")
        live_title.setObjectName("cardTitle")
        self.live_status = QLabel("Connect a wheel first")
        self.live_status.setObjectName("mutedText")
        self.live_status.setAlignment(Qt.AlignmentFlag.AlignRight)
        self.live_status.setAccessibleName("livePreviewStatus")
        live_header.addWidget(live_title)
        live_header.addStretch(1)
        live_header.addWidget(self.live_status)
        live_layout.addLayout(live_header)
        self.live_button = _button("Start live preview", "livePreviewButton", primary=True)
        live_layout.addWidget(self.live_button)
        left_col.addWidget(live_card)

        # Recording Configuration & Metadata Card
        record_card = Card()
        record_layout = QVBoxLayout(record_card)
        record_layout.setContentsMargins(18, 16, 18, 16)
        record_layout.setSpacing(10)
        rec_title = QLabel("Recording session")
        rec_title.setObjectName("cardTitle")
        record_layout.addWidget(rec_title)

        form = QFormLayout()
        form.setHorizontalSpacing(14)
        form.setVerticalSpacing(8)
        self.athlete = QLineEdit()
        self.athlete.setPlaceholderText("Athlete name / ID")
        self.athlete.setAccessibleName("athleteInput")
        self.topic = QLineEdit()
        self.topic.setPlaceholderText("e.g. Sprint, Baseline, Agility")
        self.topic.setAccessibleName("topicInput")
        self.trial = QSpinBox()
        # Keep research metadata unambiguous across Thai/English Windows locales.
        self.trial.setLocale(QLocale(QLocale.Language.English, QLocale.Country.UnitedStates))
        self.trial.setRange(1, 9999)
        self.trial.setValue(1)
        self.trial.setAccessibleName("trialInput")
        self.rate = QComboBox()
        self.rate.addItems(["50", "100", "200"])
        self.rate.setCurrentText("100")
        self.rate.setAccessibleName("sampleRateInput")
        self.tags = QLineEdit()
        self.tags.setPlaceholderText("baseline, sprint, indoor")
        self.tags.setAccessibleName("tagsInput")
        self.notes = QTextEdit()
        self.notes.setPlaceholderText("Session notes, conditions, athlete observations…")
        self.notes.setMaximumHeight(80)
        self.notes.setAccessibleName("notesInput")

        form.addRow("Athlete", self.athlete)
        form.addRow("Topic", self.topic)
        form.addRow("Trial", self.trial)
        form.addRow("Rate (Hz)", self.rate)
        form.addRow("Tags", self.tags)
        form.addRow("Notes", self.notes)
        record_layout.addLayout(form)

        rec_actions = QHBoxLayout()
        self.start_button = _button(
            "Start synchronized recording", "startRecordingButton", primary=True
        )
        self.stop_button = _button("Stop & validate", "stopRecordingButton", danger=True)
        self.stop_button.setVisible(False)
        self.countdown_label = QLabel("")
        self.countdown_label.setObjectName("cardTitle")
        self.countdown_label.setAccessibleName("recordCountdown")
        rec_actions.addWidget(self.start_button)
        rec_actions.addWidget(self.stop_button)
        rec_actions.addWidget(self.countdown_label)
        rec_actions.addStretch(1)
        record_layout.addLayout(rec_actions)
        left_col.addWidget(record_card)

        # QC Result Summary Card
        self.result = Card()
        result_layout = QVBoxLayout(self.result)
        result_layout.setContentsMargins(16, 12, 16, 12)
        self.result_title = QLabel("No finalized recording yet")
        self.result_title.setObjectName("cardTitle")
        self.result_detail = QLabel(
            "Final QC compares host, firmware and authoritative journal counts."
        )
        self.result_detail.setWordWrap(True)
        self.result_detail.setObjectName("mutedText")
        result_layout.addWidget(self.result_title)
        result_layout.addWidget(self.result_detail)
        left_col.addWidget(self.result)
        left_col.addStretch(1)

        left_container = QWidget()
        left_container.setLayout(left_col)
        left_container.setFixedWidth(400)
        main_layout.addWidget(left_container)

        # RIGHT COLUMN: Live Telemetry & Waveform Charts
        right_col = QVBoxLayout()
        right_col.setSpacing(12)

        # Current sensor sample cards (L & R)
        sensor_row = QHBoxLayout()
        self.current = {"L": CurrentSensorCard("L"), "R": CurrentSensorCard("R")}
        sensor_row.addWidget(self.current["L"])
        sensor_row.addWidget(self.current["R"])
        right_col.addLayout(sensor_row)

        # Real-time multi-axis waveform charts (4 separate charts: Accel L, Gyro L, Accel R, Gyro R)
        charts_grid = QGridLayout()
        charts_grid.setSpacing(10)
        self.accel_chart_l = MultiAxisChart("Acceleration (Left Wheel)", "g", accel_value, side="L")
        self.gyro_chart_l = MultiAxisChart("Gyroscope (Left Wheel)", "°/s", gyro_value, side="L")
        self.accel_chart_r = MultiAxisChart("Acceleration (Right Wheel)", "g", accel_value, side="R")
        self.gyro_chart_r = MultiAxisChart("Gyroscope (Right Wheel)", "°/s", gyro_value, side="R")

        # Compatibility aliases
        self.accel_chart = self.accel_chart_l
        self.gyro_chart = self.gyro_chart_l

        # Column 0: Left Wheel (Row 0: Accel L, Row 1: Gyro L)
        charts_grid.addWidget(self.accel_chart_l, 0, 0)
        charts_grid.addWidget(self.gyro_chart_l, 1, 0)
        # Column 1: Right Wheel (Row 0: Accel R, Row 1: Gyro R)
        charts_grid.addWidget(self.accel_chart_r, 0, 1)
        charts_grid.addWidget(self.gyro_chart_r, 1, 1)
        right_col.addLayout(charts_grid, 1)

        main_layout.addLayout(right_col, 1)
        root.addLayout(main_layout, 1)

        # 100ms render timer for live charts and sensor cards
        self._render = QTimer(self)
        self._render.setInterval(100)
        self._render.timeout.connect(self.render)
        self._render.start()

        self.live_button.clicked.connect(self._toggle_live)
        self.start_button.clicked.connect(self._start)
        self.stop_button.clicked.connect(controller.stop_record)

        self._countdown_timer = QTimer(self)
        self._countdown_timer.setInterval(1000)
        self._countdown_timer.timeout.connect(self._countdown_tick)
        self._countdown_remaining = 0
        self._countdown_started = False

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

    def _toggle_live(self) -> None:
        if self.controller.state.live:
            self.controller.stop_live()
        else:
            self.controller.start_live()

    def _start(self) -> None:
        self.controller.start_record(self.metadata())

    def _countdown_tick(self) -> None:
        self._countdown_remaining -= 1
        if self._countdown_remaining > 0:
            self.countdown_label.setText(f"Starting in {self._countdown_remaining}…")
            _play_tone(700, 120)
            return
        self._countdown_timer.stop()
        self.countdown_label.setText("START!")
        _play_tone(1200, 500)
        QTimer.singleShot(
            600,
            lambda: self.countdown_label.setText("Recording")
            if self.controller.state.recording
            else None,
        )

    def update_state(self, state: AppViewState) -> None:
        if state.live_busy:
            self.live_button.setText("Please wait…")
            self.live_status.setText("Updating stream safely")
        elif state.live:
            self.live_button.setText("Stop live preview")
            self.live_status.setText(f"Streaming: {' + '.join(state.live_sides)}")
        else:
            self.live_button.setText("Start live preview")
            self.live_status.setText(
                "Ready to stream" if state.connected_sides() else "Connect a wheel first"
            )
        self.live_button.setEnabled(
            bool(state.connected_sides())
            and state.daemon_connected
            and not state.recording
            and not state.recording_starting
            and not state.live_busy
        )

        can_start = (
            bool(state.connected_sides())
            and state.daemon_connected
            and not state.recording
            and not state.recording_starting
            and not state.live_busy
        )
        self.start_button.setEnabled(can_start)
        self.start_button.setVisible(not state.recording)
        self.start_button.setText(
            "Preparing recording…" if state.recording_starting else "Start synchronized recording"
        )
        self.stop_button.setVisible(state.recording)
        self.stop_button.setEnabled(state.recording)

        if state.countdown is not None and not self._countdown_started:
            self._countdown_started = True
            self._countdown_remaining = state.countdown
            self.countdown_label.setText(f"Starting in {state.countdown}…")
            _play_tone(700, 120)
            self._countdown_timer.start()
        elif not state.recording_starting and not state.recording:
            self._countdown_timer.stop()
            self._countdown_started = False
            self.countdown_label.clear()
        elif state.recording and not self._countdown_timer.isActive():
            self.countdown_label.setText("Recording")

        for widget in (self.athlete, self.topic, self.trial, self.rate, self.tags, self.notes):
            widget.setEnabled(not state.recording and not state.recording_starting)

        self.render_current()

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
        self.accel_chart_l.update_from_controller(self.controller)
        self.gyro_chart_l.update_from_controller(self.controller)
        self.accel_chart_r.update_from_controller(self.controller)
        self.gyro_chart_r.update_from_controller(self.controller)

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
            text = (
                "All recorded integrity checks passed."
                if quality == "GOOD"
                else "No additional QC reason was supplied."
            )
        if result.get("demo"):
            text = "DEMO ONLY — synthetic preview was not written as research evidence."
        self.result_detail.setText(text)


LivePage = AcquisitionPage
RecordPage = AcquisitionPage


class SessionPreviewDrawer(Card):
    """Real-time multi-axis waveform previewer with signal loss and gap detection."""

    closed = Signal()

    def __init__(self, controller: BaseController, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.controller = controller
        self.setObjectName("previewCard")
        self._current_session_id = ""

        layout = QVBoxLayout(self)
        layout.setContentsMargins(18, 14, 18, 14)
        layout.setSpacing(12)

        # Header bar
        header = QHBoxLayout()
        self.title = QLabel("Recording Telemetry Preview")
        self.title.setObjectName("cardTitle")
        self.meta_label = QLabel("Select a trial to view real-time acceleration and gyroscope curves")
        self.meta_label.setObjectName("mutedText")

        self.export_csv_btn = _button("Export this CSV", "exportPreviewCsvBtn", primary=True)
        self.export_csv_btn.setEnabled(False)
        self.close_btn = _button("Close Preview", "closePreviewBtn")

        header.addWidget(self.title)
        header.addSpacing(10)
        header.addWidget(self.meta_label, 1)
        header.addWidget(self.export_csv_btn)
        header.addWidget(self.close_btn)
        layout.addLayout(header)

        # Signal Integrity / Loss Card
        self.integrity_card = QFrame()
        self.integrity_card.setObjectName("card")
        int_layout = QHBoxLayout(self.integrity_card)
        int_layout.setContentsMargins(14, 10, 14, 10)
        self.integrity_badge = QLabel("Lossless (100% contiguous data)")
        self.integrity_badge.setObjectName("previewLossGood")
        self.integrity_detail = QLabel("No sequence gaps or dropped samples detected")
        self.integrity_detail.setObjectName("mutedText")
        self.integrity_detail.setWordWrap(True)
        int_layout.addWidget(self.integrity_badge)
        int_layout.addWidget(self.integrity_detail, 1)
        layout.addWidget(self.integrity_card)

        # 4-Chart Waveform Grid (Column 0 = Left Wheel, Column 1 = Right Wheel)
        charts_grid = QGridLayout()
        charts_grid.setSpacing(10)

        axis_colors = {
            "X": QColor("#0284c7"),  # Sky Blue
            "Y": QColor("#16a34a"),  # Emerald Green
            "Z": QColor("#ea580c"),  # Coral Orange
        }

        def _create_chart(title: str, y_label: str, side_label: str):
            chart = QChart()
            chart.setTitle(f"{title} ({side_label})")
            t_font = QFont()
            t_font.setPointSize(10)
            t_font.setBold(True)
            chart.setTitleFont(t_font)
            chart.legend().setVisible(True)
            chart.legend().setAlignment(Qt.AlignmentFlag.AlignBottom)
            chart.setAnimationOptions(QChart.AnimationOption.NoAnimation)

            x_axis = QValueAxis()
            x_axis.setTitleText("Time (s)")
            y_axis = QValueAxis()
            y_axis.setTitleText(y_label)
            chart.addAxis(x_axis, Qt.AlignmentFlag.AlignBottom)
            chart.addAxis(y_axis, Qt.AlignmentFlag.AlignLeft)

            series_map: dict[str, QLineSeries] = {}
            for axis in ("X", "Y", "Z"):
                s = QLineSeries()
                s.setName(f"{axis}")
                pen = QPen(axis_colors[axis])
                pen.setWidthF(1.8)
                s.setPen(pen)
                chart.addSeries(s)
                s.attachAxis(x_axis)
                s.attachAxis(y_axis)
                series_map[axis] = s

            gap_scatter = QScatterSeries()
            gap_scatter.setName("Signal Loss")
            gap_scatter.setColor(QColor("#dc2626"))
            gap_scatter.setMarkerSize(8.0)
            chart.addSeries(gap_scatter)
            gap_scatter.attachAxis(x_axis)
            gap_scatter.attachAxis(y_axis)

            view = QChartView(chart)
            style_chart_surface(chart, view)
            view.setRenderHint(QPainter.RenderHint.Antialiasing, False)
            view.setMinimumHeight(180)
            return chart, x_axis, y_axis, series_map, gap_scatter, view

        # 1. Left Wheel Acceleration (Row 0, Col 0)
        self.accel_chart_l, self.accel_x_axis_l, self.accel_y_axis_l, self.accel_series_l, self.accel_gap_scatter_l, view_al = _create_chart("Acceleration", "g", "Left Wheel")
        # 2. Left Wheel Gyroscope (Row 1, Col 0)
        self.gyro_chart_l, self.gyro_x_axis_l, self.gyro_y_axis_l, self.gyro_series_l, self.gyro_gap_scatter_l, view_gl = _create_chart("Gyroscope", "°/s", "Left Wheel")
        # 3. Right Wheel Acceleration (Row 0, Col 1)
        self.accel_chart_r, self.accel_x_axis_r, self.accel_y_axis_r, self.accel_series_r, self.accel_gap_scatter_r, view_ar = _create_chart("Acceleration", "g", "Right Wheel")
        # 4. Right Wheel Gyroscope (Row 1, Col 1)
        self.gyro_chart_r, self.gyro_x_axis_r, self.gyro_y_axis_r, self.gyro_series_r, self.gyro_gap_scatter_r, view_gr = _create_chart("Gyroscope", "°/s", "Right Wheel")

        # Add to grid: Left column = Left Wheel, Right column = Right Wheel
        charts_grid.addWidget(view_al, 0, 0)
        charts_grid.addWidget(view_gl, 1, 0)
        charts_grid.addWidget(view_ar, 0, 1)
        charts_grid.addWidget(view_gr, 1, 1)
        layout.addLayout(charts_grid)

        # Backward compatibility aliases
        self.accel_chart = self.accel_chart_l
        self.gyro_chart = self.gyro_chart_l
        self.accel_x_axis = self.accel_x_axis_l
        self.accel_y_axis = self.accel_y_axis_l
        self.gyro_x_axis = self.gyro_x_axis_l
        self.gyro_y_axis = self.gyro_y_axis_l
        self.accel_gap_scatter = self.accel_gap_scatter_l
        self.gyro_gap_scatter = self.gyro_gap_scatter_l
        self.accel_series = {
            "L_X": self.accel_series_l["X"], "L_Y": self.accel_series_l["Y"], "L_Z": self.accel_series_l["Z"],
            "R_X": self.accel_series_r["X"], "R_Y": self.accel_series_r["Y"], "R_Z": self.accel_series_r["Z"],
        }
        self.gyro_series = {
            "L_X": self.gyro_series_l["X"], "L_Y": self.gyro_series_l["Y"], "L_Z": self.gyro_series_l["Z"],
            "R_X": self.gyro_series_r["X"], "R_Y": self.gyro_series_r["Y"], "R_Z": self.gyro_series_r["Z"],
        }

        self.close_btn.clicked.connect(self._close_requested)
        self.export_csv_btn.clicked.connect(self._export_current)

    def _close_requested(self) -> None:
        self.hide()
        self.closed.emit()

    def _export_current(self) -> None:
        if not self._current_session_id:
            return
        default_dir = str(Path.home() / "Documents" / "WheelAthlete" / "Exports")
        chosen = QFileDialog.getExistingDirectory(self, "Select Export Directory", default_dir)
        if chosen:
            match = next(
                (s for s in self.controller.sessions if s.get("session_id") == self._current_session_id),
                {"session_id": self._current_session_id},
            )
            self.controller.export_sessions([match], chosen)

    def load_session(self, session_id: str) -> None:
        self._current_session_id = session_id
        data = self.controller.load_session_data(session_id)
        topic = data.get("topic") or "General"
        trial = data.get("trial_number")
        trial_str = f"Trial {trial}" if trial else "Trial —"
        athlete = data.get("athlete") or "Athlete —"
        duration_s = float(data.get("duration_s", 0.0) or 0.0)
        rate_hz = data.get("sample_rate_hz", 100)

        self.title.setText(f"Telemetry Preview: {topic} — {trial_str} — {athlete}")
        self.meta_label.setText(f"Rate: {rate_hz} Hz   •   Duration: {duration_s:.1f} s   •   ID: {session_id}")
        self.export_csv_btn.setEnabled(True)

        gaps = data.get("gaps", [])
        total_missing = data.get("total_missing_samples", 0)
        if not gaps and total_missing == 0:
            self.integrity_badge.setText("Lossless (100% contiguous data)")
            self.integrity_badge.setObjectName("previewLossGood")
            self.integrity_detail.setText("All packets arrived sequentially without drops.")
        else:
            gap_summary = ", ".join(f"t={g['time_s']:.1f}s ({g['side']}: -{g.get('missing', 1)})" for g in gaps[:5])
            if len(gaps) > 5:
                gap_summary += f" ... +{len(gaps) - 5} more"
            self.integrity_badge.setText(f"Signal Loss: {total_missing} missing samples ({len(gaps)} gap events)")
            self.integrity_badge.setObjectName("previewLossWarn")
            self.integrity_detail.setText(f"Detected drops at: {gap_summary}")

        self.integrity_badge.style().unpolish(self.integrity_badge)
        self.integrity_badge.style().polish(self.integrity_badge)

        samples_l = data.get("samples", {}).get("L", [])
        samples_r = data.get("samples", {}).get("R", [])

        max_t = max(duration_s, 1.0)
        for x_axis in (self.accel_x_axis_l, self.gyro_x_axis_l, self.accel_x_axis_r, self.gyro_x_axis_r):
            x_axis.setRange(0, max_t)

        all_accel_l: list[float] = []
        all_gyro_l: list[float] = []
        all_accel_r: list[float] = []
        all_gyro_r: list[float] = []

        step_l = max(1, len(samples_l) // 2500)
        step_r = max(1, len(samples_r) // 2500)

        pts_ax_l, pts_ay_l, pts_az_l = [], [], []
        pts_gx_l, pts_gy_l, pts_gz_l = [], [], []
        for s in samples_l[::step_l]:
            t = s["t"]
            pts_ax_l.append(QPointF(t, s["ax"]))
            pts_ay_l.append(QPointF(t, s["ay"]))
            pts_az_l.append(QPointF(t, s["az"]))
            pts_gx_l.append(QPointF(t, s["gx"]))
            pts_gy_l.append(QPointF(t, s["gy"]))
            pts_gz_l.append(QPointF(t, s["gz"]))
            all_accel_l.extend([s["ax"], s["ay"], s["az"]])
            all_gyro_l.extend([s["gx"], s["gy"], s["gz"]])

        self.accel_series_l["X"].replace(pts_ax_l)
        self.accel_series_l["Y"].replace(pts_ay_l)
        self.accel_series_l["Z"].replace(pts_az_l)
        self.gyro_series_l["X"].replace(pts_gx_l)
        self.gyro_series_l["Y"].replace(pts_gy_l)
        self.gyro_series_l["Z"].replace(pts_gz_l)

        pts_ax_r, pts_ay_r, pts_az_r = [], [], []
        pts_gx_r, pts_gy_r, pts_gz_r = [], [], []
        for s in samples_r[::step_r]:
            t = s["t"]
            pts_ax_r.append(QPointF(t, s["ax"]))
            pts_ay_r.append(QPointF(t, s["ay"]))
            pts_az_r.append(QPointF(t, s["az"]))
            pts_gx_r.append(QPointF(t, s["gx"]))
            pts_gy_r.append(QPointF(t, s["gy"]))
            pts_gz_r.append(QPointF(t, s["gz"]))
            all_accel_r.extend([s["ax"], s["ay"], s["az"]])
            all_gyro_r.extend([s["gx"], s["gy"], s["gz"]])

        self.accel_series_r["X"].replace(pts_ax_r)
        self.accel_series_r["Y"].replace(pts_ay_r)
        self.accel_series_r["Z"].replace(pts_az_r)
        self.gyro_series_r["X"].replace(pts_gx_r)
        self.gyro_series_r["Y"].replace(pts_gy_r)
        self.gyro_series_r["Z"].replace(pts_gz_r)

        gap_accel_l, gap_gyro_l = [], []
        gap_accel_r, gap_gyro_r = [], []
        for g in gaps:
            gt = float(g.get("time_s", 0.0))
            if g.get("side") == "L":
                gap_accel_l.append(QPointF(gt, 0.0))
                gap_gyro_l.append(QPointF(gt, 0.0))
            elif g.get("side") == "R":
                gap_accel_r.append(QPointF(gt, 0.0))
                gap_gyro_r.append(QPointF(gt, 0.0))
            else:
                gap_accel_l.append(QPointF(gt, 0.0))
                gap_gyro_l.append(QPointF(gt, 0.0))
                gap_accel_r.append(QPointF(gt, 0.0))
                gap_gyro_r.append(QPointF(gt, 0.0))

        self.accel_gap_scatter_l.replace(gap_accel_l)
        self.gyro_gap_scatter_l.replace(gap_gyro_l)
        self.accel_gap_scatter_r.replace(gap_accel_r)
        self.gyro_gap_scatter_r.replace(gap_gyro_r)

        if all_accel_l:
            max_al = max(0.5, max(abs(v) for v in all_accel_l)) * 1.15
            self.accel_y_axis_l.setRange(-max_al, max_al)
        if all_gyro_l:
            max_gl = max(10.0, max(abs(v) for v in all_gyro_l)) * 1.15
            self.gyro_y_axis_l.setRange(-max_gl, max_gl)
        if all_accel_r:
            max_ar = max(0.5, max(abs(v) for v in all_accel_r)) * 1.15
            self.accel_y_axis_r.setRange(-max_ar, max_ar)
        if all_gyro_r:
            max_gr = max(10.0, max(abs(v) for v in all_gyro_r)) * 1.15
            self.gyro_y_axis_r.setRange(-max_gr, max_gr)

        self.show()


class TopicCard(Card):
    """Collapsible card displaying a single topic's summary and expandable trials list."""

    selection_changed = Signal()
    preview_requested = Signal(str)

    def __init__(self, topic: str, sessions: list[dict[str, Any]], parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.topic = topic
        self.sessions = list(sessions)
        self.setObjectName("topicCard")
        self.setProperty("expanded", False)
        self._block_signals = False

        self.root_layout = QVBoxLayout(self)
        self.root_layout.setContentsMargins(16, 14, 16, 14)
        self.root_layout.setSpacing(10)

        header = QHBoxLayout()
        header.setSpacing(12)

        self.check = QCheckBox()
        self.check.setToolTip("Select all trials in this topic")
        header.addWidget(self.check)

        self.title_label = QLabel(self.topic)
        self.title_label.setObjectName("topicTitle")
        header.addWidget(self.title_label)

        trials_count = len(self.sessions)
        self.count_pill = QLabel(f"{trials_count} Trial{'s' if trials_count != 1 else ''}")
        self.count_pill.setObjectName("topicCountPill")
        header.addWidget(self.count_pill)

        athletes = sorted({str(s.get("athlete", "")).strip() for s in self.sessions if s.get("athlete")})
        athletes_text = f"Athletes: {', '.join(athletes)}" if athletes else "Athletes: —"
        self.athletes_pill = QLabel(athletes_text)
        self.athletes_pill.setObjectName("topicAthletesPill")
        self.athletes_pill.setSizePolicy(
            QSizePolicy.Policy.Maximum,
            QSizePolicy.Policy.Preferred,
        )
        self.athletes_pill.setMaximumWidth(220)
        self.athletes_pill.setToolTip(athletes_text)
        header.addWidget(self.athletes_pill)

        total_dur = sum(float(s.get("duration_s", 0) or 0) for s in self.sessions)
        self.duration_label = QLabel(f"Total: {fmt(total_dur, ' s', 1)}")
        self.duration_label.setObjectName("mutedText")
        header.addWidget(self.duration_label)

        qualities = [str(s.get("quality", "GOOD")) for s in self.sessions]
        overall_qc = "INVALID" if "INVALID" in qualities else "DEGRADED" if "DEGRADED" in qualities else "WARNING" if "WARNING" in qualities else "GOOD"
        self.qc_pill = QLabel(overall_qc)
        self.qc_pill.setObjectName("statusPill")
        self.qc_pill.setProperty("state", "good" if overall_qc == "GOOD" else "warning")
        header.addWidget(self.qc_pill)

        header.addStretch(1)

        self.toggle_btn = QPushButton(f"View Trials ({trials_count})")
        self.toggle_btn.setObjectName("seeMoreButton")
        header.addWidget(self.toggle_btn)

        self.root_layout.addLayout(header)

        self.table_container = QWidget()
        self.table_container.setStyleSheet("background-color: #ffffff;")
        table_layout = QVBoxLayout(self.table_container)
        table_layout.setContentsMargins(0, 8, 0, 0)
        table_layout.setSpacing(6)

        self.table = QTableWidget(len(self.sessions), 9)
        self.table.setHorizontalHeaderLabels([
            "Select",
            "Quality",
            "Trial",
            "Athlete",
            "Rate",
            "Duration",
            "L samples",
            "R samples",
            "Preview",
        ])
        self.table.verticalHeader().setVisible(False)
        self.table.verticalHeader().setDefaultSectionSize(40)
        self.table.setItemDelegateForColumn(0, CheckBoxDelegate(self.table))
        self.table.setSelectionBehavior(QAbstractItemView.SelectionBehavior.SelectRows)
        self.table.setAlternatingRowColors(True)

        self.table.horizontalHeader().setSectionResizeMode(0, QHeaderView.ResizeMode.Fixed)
        self.table.setColumnWidth(0, 48)
        self.table.horizontalHeader().setSectionResizeMode(1, QHeaderView.ResizeMode.Fixed)
        self.table.setColumnWidth(1, 75)
        self.table.horizontalHeader().setSectionResizeMode(2, QHeaderView.ResizeMode.Fixed)
        self.table.setColumnWidth(2, 75)
        self.table.horizontalHeader().setSectionResizeMode(3, QHeaderView.ResizeMode.Stretch)
        self.table.horizontalHeader().setSectionResizeMode(4, QHeaderView.ResizeMode.Fixed)
        self.table.setColumnWidth(4, 75)
        self.table.horizontalHeader().setSectionResizeMode(5, QHeaderView.ResizeMode.Fixed)
        self.table.setColumnWidth(5, 80)
        self.table.horizontalHeader().setSectionResizeMode(6, QHeaderView.ResizeMode.Fixed)
        self.table.setColumnWidth(6, 85)
        self.table.horizontalHeader().setSectionResizeMode(7, QHeaderView.ResizeMode.Fixed)
        self.table.setColumnWidth(7, 85)
        self.table.horizontalHeader().setSectionResizeMode(8, QHeaderView.ResizeMode.Fixed)
        self.table.setColumnWidth(8, 110)
        self.table.horizontalHeaderItem(8).setTextAlignment(Qt.AlignmentFlag.AlignCenter)

        self._active_session_id = ""
        self._populate_table()
        table_layout.addWidget(self.table)
        self.table_container.hide()
        self.root_layout.addWidget(self.table_container)

        self.toggle_btn.clicked.connect(self.toggle_expanded)
        self.check.toggled.connect(self._on_topic_check_toggled)
        self.table.itemChanged.connect(self._on_table_item_changed)

    def _populate_table(self) -> None:
        self._block_signals = True
        self.table.setRowCount(len(self.sessions))
        for row, item in enumerate(self.sessions):
            self.table.setRowHeight(row, 40)
            check_item = QTableWidgetItem()
            check_item.setFlags(Qt.ItemFlag.ItemIsUserCheckable | Qt.ItemFlag.ItemIsEnabled | Qt.ItemFlag.ItemIsSelectable)
            check_item.setCheckState(Qt.CheckState.Unchecked)
            self.table.setItem(row, 0, check_item)

            counts = item.get("sample_counts") if isinstance(item.get("sample_counts"), dict) else {}
            tr = item.get("trial_number", "—")
            tr_str = f"Trial {tr}" if tr != "—" else "—"
            values = [
                str(item.get("quality", "GOOD")),
                tr_str,
                str(item.get("athlete", "—")),
                f"{item.get('sample_rate_hz', '—')} Hz",
                fmt(item.get("duration_s"), " s", 1),
                f"{int(counts.get('L', 0) or 0):,}",
                f"{int(counts.get('R', 0) or 0):,}",
            ]
            for col, val in enumerate(values, start=1):
                cell = QTableWidgetItem(val)
                cell.setFlags(Qt.ItemFlag.ItemIsEnabled | Qt.ItemFlag.ItemIsSelectable)
                if col in (1, 2):
                    cell.setTextAlignment(Qt.AlignmentFlag.AlignCenter)
                elif col in (4, 5, 6, 7):
                    cell.setTextAlignment(Qt.AlignmentFlag.AlignRight | Qt.AlignmentFlag.AlignVCenter)
                else:
                    cell.setTextAlignment(Qt.AlignmentFlag.AlignLeft | Qt.AlignmentFlag.AlignVCenter)
                self.table.setItem(row, col, cell)

            sess_id = str(item.get("session_id", ""))
            is_active = (sess_id == self._active_session_id and bool(sess_id))
            action_widget = _table_action_button(
                "Viewing" if is_active else "Preview",
                "previewTableBtn",
                lambda _=None, s=sess_id: self.preview_requested.emit(s),
                active=is_active,
            )
            self.table.setCellWidget(row, 8, action_widget)

        self._block_signals = False

    def set_active_preview(self, session_id: str) -> None:
        self._active_session_id = session_id
        for row, item in enumerate(self.sessions):
            sess_id = str(item.get("session_id", ""))
            is_active = (sess_id == session_id and bool(session_id))
            action_widget = _table_action_button(
                "Viewing" if is_active else "Preview",
                "previewTableBtn",
                lambda _=None, s=sess_id: self.preview_requested.emit(s),
                active=is_active,
            )
            self.table.setCellWidget(row, 8, action_widget)

    def toggle_expanded(self) -> None:
        self.set_expanded(not self.table_container.isVisible())

    def set_expanded(self, expanded: bool) -> None:
        self.table_container.setVisible(expanded)
        self.setProperty("expanded", expanded)
        self.style().unpolish(self)
        self.style().polish(self)
        trials_count = len(self.sessions)
        if expanded:
            self.toggle_btn.setText("Hide Trials")
            row_h = self.table.verticalHeader().defaultSectionSize() or 38
            header_h = self.table.horizontalHeader().height() or 34
            total_h = header_h + row_h * len(self.sessions) + 6
            # Let the frame follow its content, with a bounded table viewport
            # for unusually large topics.
            self.table.setMinimumHeight(min(380, total_h))
            self.table.setMaximumHeight(380)
        else:
            self.toggle_btn.setText(f"View Trials ({trials_count})")
            self.table.setMinimumHeight(0)
            self.table.setMaximumHeight(16777215)

    def _on_topic_check_toggled(self, checked: bool) -> None:
        if self._block_signals:
            return
        self._block_signals = True
        state = Qt.CheckState.Checked if checked else Qt.CheckState.Unchecked
        for row in range(self.table.rowCount()):
            it = self.table.item(row, 0)
            if it is not None:
                it.setCheckState(state)
            self._highlight_row(row, checked)
        self._block_signals = False
        self.selection_changed.emit()

    def _on_table_item_changed(self, item: QTableWidgetItem) -> None:
        if self._block_signals:
            return
        if item.column() == 0:
            is_checked = (
                item.checkState() in (Qt.CheckState.Checked, Qt.CheckState.Checked.value, 2)
                or item.data(Qt.ItemDataRole.CheckStateRole) in (Qt.CheckState.Checked, Qt.CheckState.Checked.value, 2)
            )
            self._highlight_row(item.row(), is_checked)
            self._sync_topic_check()
            self.selection_changed.emit()

    def _highlight_row(self, row: int, is_checked: bool) -> None:
        bg_color = QColor("#f0fdfa") if is_checked else QColor("#ffffff")
        for col in range(self.table.columnCount()):
            it = self.table.item(row, col)
            if it is not None:
                it.setBackground(bg_color)

    def _sync_topic_check(self) -> None:
        checked_count = sum(
            1 for r in range(self.table.rowCount())
            if self.table.item(r, 0) and (
                self.table.item(r, 0).checkState() in (Qt.CheckState.Checked, Qt.CheckState.Checked.value, 2)
                or self.table.item(r, 0).data(Qt.ItemDataRole.CheckStateRole) in (Qt.CheckState.Checked, Qt.CheckState.Checked.value, 2)
            )
        )
        self._block_signals = True
        self.check.setChecked(checked_count == self.table.rowCount() and self.table.rowCount() > 0)
        self._block_signals = False

    def select_all(self, checked: bool) -> None:
        self._block_signals = True
        self.check.setChecked(checked)
        state = Qt.CheckState.Checked if checked else Qt.CheckState.Unchecked
        for row in range(self.table.rowCount()):
            it = self.table.item(row, 0)
            if it is not None:
                it.setCheckState(state)
            self._highlight_row(row, checked)
        self._block_signals = False

    def get_selected_sessions(self) -> list[dict[str, Any]]:
        selected = []
        for row in range(self.table.rowCount()):
            it = self.table.item(row, 0)
            if it is not None:
                is_checked = (
                    it.checkState() in (Qt.CheckState.Checked, Qt.CheckState.Checked.value, 2)
                    or it.data(Qt.ItemDataRole.CheckStateRole) in (Qt.CheckState.Checked, Qt.CheckState.Checked.value, 2)
                )
                if is_checked and row < len(self.sessions):
                    selected.append(self.sessions[row])
        return selected


class ResultsPage(QWidget):
    """Hierarchical Topic browser with expandable trials, multi-file CSV export into topic subfolders, and real telemetry preview."""

    def __init__(self, controller: BaseController) -> None:
        super().__init__()
        self.controller = controller
        self._sessions: list[dict[str, Any]] = []
        self._visible: list[dict[str, Any]] = []
        self._topic_cards: list[TopicCard] = []
        self._block_table_signals = False

        root = QVBoxLayout(self)
        root.setContentsMargins(24, 20, 24, 20)
        root.setSpacing(14)
        root.addLayout(
            _page_header(
                "Recording results & CSV export",
                "Browse recordings by topic, expand to inspect individual trials and athletes, preview real telemetry with signal loss detection, and batch export.",
            )
        )

        # Session Folder Card
        folder_card = Card()
        folder_layout = QHBoxLayout(folder_card)
        folder_layout.setContentsMargins(16, 12, 16, 12)
        folder_layout.setSpacing(10)

        folder_title = QLabel("Session folder:")
        folder_title.setObjectName("cardTitle")
        self.folder_label = QLabel(self.controller.state.journal_root or "Default folder")
        self.folder_label.setObjectName("mutedText")
        self.folder_label.setTextInteractionFlags(Qt.TextInteractionFlag.TextSelectableByMouse)
        self.change_folder_button = _button("Change folder…", "changeSessionFolderButton")
        self.open_folder_button = _button("Open session folder", "openSessionFolderButton")
        self.refresh_button = _button("Refresh", "refreshSessionsButton")

        folder_layout.addWidget(folder_title)
        folder_layout.addWidget(self.folder_label, 1)
        folder_layout.addWidget(self.change_folder_button)
        folder_layout.addWidget(self.open_folder_button)
        folder_layout.addWidget(self.refresh_button)
        root.addWidget(folder_card)

        # Filters & Actions Bar
        filter_card = Card()
        filter_layout = QHBoxLayout(filter_card)
        filter_layout.setContentsMargins(16, 10, 16, 10)
        filter_layout.setSpacing(10)

        self.search = QLineEdit()
        self.search.setPlaceholderText("Search athlete, topic, session ID…")
        self.search.setAccessibleName("sessionSearch")

        self.topic_filter = QComboBox()
        self.topic_filter.addItem("All topics")
        self.topic_filter.setAccessibleName("topicFilter")

        self.trial_filter = QComboBox()
        self.trial_filter.addItem("All trials")
        self.trial_filter.setAccessibleName("trialFilter")

        self.select_all_btn = _button("Select all", "selectAllButton")
        self.deselect_all_btn = _button("Deselect all", "deselectAllButton")

        self.export_button = _button("Export selected CSV(s)", "exportSessionButton", primary=True)
        self.delete_button = _button("Delete selected", "deleteSessionButton", danger=True)

        filter_layout.addWidget(QLabel("Filter:"))
        filter_layout.addWidget(self.search, 2)
        filter_layout.addWidget(self.topic_filter, 1)
        filter_layout.addWidget(self.trial_filter, 1)
        filter_layout.addWidget(self.select_all_btn)
        filter_layout.addWidget(self.deselect_all_btn)
        filter_layout.addWidget(self.export_button)
        filter_layout.addWidget(self.delete_button)
        root.addWidget(filter_card)

        # Telemetry Preview Drawer (Collapsible)
        self.preview_drawer = SessionPreviewDrawer(self.controller, self)
        self.preview_drawer.hide()
        root.addWidget(self.preview_drawer)

        # Tab Widget for Group by Topic vs Flat Table
        self.view_tabs = QTabWidget()
        self.view_tabs.setObjectName("viewTabs")

        # Tab 1: Topic Grouped View (Primary)
        self.topic_scroll = QScrollArea()
        self.topic_scroll.setWidgetResizable(True)
        self.topic_scroll.setFrameShape(QFrame.Shape.NoFrame)
        self.topic_container = QWidget()
        self.topic_layout = QVBoxLayout(self.topic_container)
        self.topic_layout.setContentsMargins(0, 4, 0, 4)
        self.topic_layout.setSpacing(10)
        self.topic_layout.addStretch(1)
        self.topic_scroll.setWidget(self.topic_container)
        self.view_tabs.addTab(self.topic_scroll, "Group by Topic")

        # Tab 2: Flat Table View
        flat_container = QWidget()
        flat_layout = QVBoxLayout(flat_container)
        flat_layout.setContentsMargins(0, 4, 0, 0)
        self.table = QTableWidget(0, 10)
        self.table.setHorizontalHeaderLabels([
            "Select",
            "Quality",
            "Topic",
            "Trial",
            "Athlete",
            "Rate",
            "Duration",
            "L samples",
            "R samples",
            "Preview",
        ])
        self.table.verticalHeader().setVisible(False)
        self.table.verticalHeader().setDefaultSectionSize(40)
        self.table.setItemDelegateForColumn(0, CheckBoxDelegate(self.table))
        self.table.horizontalHeader().setSectionResizeMode(0, QHeaderView.ResizeMode.Fixed)
        self.table.setColumnWidth(0, 48)
        self.table.horizontalHeader().setSectionResizeMode(1, QHeaderView.ResizeMode.Fixed)
        self.table.setColumnWidth(1, 75)
        self.table.horizontalHeader().setSectionResizeMode(2, QHeaderView.ResizeMode.Fixed)
        self.table.setColumnWidth(2, 110)
        self.table.horizontalHeader().setSectionResizeMode(3, QHeaderView.ResizeMode.Fixed)
        self.table.setColumnWidth(3, 75)
        self.table.horizontalHeader().setSectionResizeMode(4, QHeaderView.ResizeMode.Stretch)
        self.table.horizontalHeader().setSectionResizeMode(5, QHeaderView.ResizeMode.Fixed)
        self.table.setColumnWidth(5, 75)
        self.table.horizontalHeader().setSectionResizeMode(6, QHeaderView.ResizeMode.Fixed)
        self.table.setColumnWidth(6, 80)
        self.table.horizontalHeader().setSectionResizeMode(7, QHeaderView.ResizeMode.Fixed)
        self.table.setColumnWidth(7, 85)
        self.table.horizontalHeader().setSectionResizeMode(8, QHeaderView.ResizeMode.Fixed)
        self.table.setColumnWidth(8, 85)
        self.table.horizontalHeader().setSectionResizeMode(9, QHeaderView.ResizeMode.Fixed)
        self.table.setColumnWidth(9, 110)
        self.table.horizontalHeaderItem(9).setTextAlignment(Qt.AlignmentFlag.AlignCenter)
        self.table.setSelectionBehavior(QAbstractItemView.SelectionBehavior.SelectRows)
        self.table.setSelectionMode(QAbstractItemView.SelectionMode.ExtendedSelection)
        self.table.setAlternatingRowColors(True)
        self.table.setAccessibleName("sessionsTable")
        flat_layout.addWidget(self.table)
        self.view_tabs.addTab(flat_container, "All Trials Table")

        root.addWidget(self.view_tabs, 1)

        # Backward compatibility aliases
        self.export = self.export_button
        self.delete = self.delete_button
        self.open_folder = self.open_folder_button
        self.refresh = self.refresh_button

        self.search.textChanged.connect(self._filter)
        self.topic_filter.currentTextChanged.connect(self._filter)
        self.trial_filter.currentTextChanged.connect(self._filter)
        self.select_all_btn.clicked.connect(self._select_all)
        self.deselect_all_btn.clicked.connect(self._deselect_all)
        self.refresh_button.clicked.connect(controller.refresh_sessions)
        self.change_folder_button.clicked.connect(self._change_folder)
        self.open_folder_button.clicked.connect(self._open_folder)
        self.export_button.clicked.connect(self._export_selected)
        self.delete_button.clicked.connect(self._delete_selected)
        self.table.itemChanged.connect(self._on_table_item_changed)
        self.preview_drawer.closed.connect(self._on_preview_closed)

        self._active_session_id = ""
        controller.sessions_changed.connect(self.update_sessions)
        controller.state_changed.connect(self._update_state)
        self.update_sessions(controller.sessions)
        self._update_state(controller.state)

    def _update_state(self, state: AppViewState) -> None:
        self.folder_label.setText(state.journal_root or "Default folder")

    def update_sessions(self, sessions: list[dict[str, Any]]) -> None:
        self._sessions = list(sessions)

        # Update topic filter combo
        current_topic = self.topic_filter.currentText()
        topics = sorted({str(s.get("topic", "")).strip() for s in self._sessions if s.get("topic")})
        self.topic_filter.blockSignals(True)
        self.topic_filter.clear()
        self.topic_filter.addItem("All topics")
        for t in topics:
            self.topic_filter.addItem(t)
        idx = self.topic_filter.findText(current_topic)
        self.topic_filter.setCurrentIndex(idx if idx >= 0 else 0)
        self.topic_filter.blockSignals(False)

        # Update trial filter combo
        current_trial = self.trial_filter.currentText()
        trials = sorted({str(s.get("trial_number", "")) for s in self._sessions if s.get("trial_number") is not None})
        self.trial_filter.blockSignals(True)
        self.trial_filter.clear()
        self.trial_filter.addItem("All trials")
        for tr in trials:
            if tr:
                self.trial_filter.addItem(f"Trial {tr}")
        idx = self.trial_filter.findText(current_trial)
        self.trial_filter.setCurrentIndex(idx if idx >= 0 else 0)
        self.trial_filter.blockSignals(False)

        self._filter()

    def _filter(self) -> None:
        query = self.search.text().strip().lower()
        selected_topic = self.topic_filter.currentText()
        selected_trial = self.trial_filter.currentText()

        self._visible = []
        for item in self._sessions:
            item_topic = str(item.get("topic", "")).strip()
            item_trial = str(item.get("trial_number", ""))
            if selected_topic != "All topics" and item_topic != selected_topic:
                continue
            if selected_trial != "All trials" and f"Trial {item_trial}" != selected_trial and item_trial != selected_trial:
                continue
            haystack = " ".join(
                str(item.get(key, ""))
                for key in ("session_id", "athlete", "topic", "quality", "trial_number")
            ).lower()
            if not query or query in haystack:
                self._visible.append(item)

        # 1. Populate Flat Table
        self._block_table_signals = True
        self.table.setRowCount(len(self._visible))
        for row, item in enumerate(self._visible):
            self.table.setRowHeight(row, 40)
            check_item = QTableWidgetItem()
            check_item.setFlags(Qt.ItemFlag.ItemIsUserCheckable | Qt.ItemFlag.ItemIsEnabled | Qt.ItemFlag.ItemIsSelectable)
            check_item.setCheckState(Qt.CheckState.Unchecked)
            self.table.setItem(row, 0, check_item)

            counts = item.get("sample_counts") if isinstance(item.get("sample_counts"), dict) else {}
            values = [
                str(item.get("quality", "—")),
                str(item.get("topic", "")),
                str(item.get("trial_number", "—")),
                str(item.get("athlete", "")),
                f"{item.get('sample_rate_hz', '—')} Hz",
                fmt(item.get("duration_s"), " s", 1),
                f"{int(counts.get('L', 0) or 0):,}",
                f"{int(counts.get('R', 0) or 0):,}",
            ]
            for col, value in enumerate(values, start=1):
                cell = QTableWidgetItem(value)
                cell.setFlags(Qt.ItemFlag.ItemIsEnabled | Qt.ItemFlag.ItemIsSelectable)
                if col in (1, 3):
                    cell.setTextAlignment(Qt.AlignmentFlag.AlignCenter)
                elif col in (5, 6, 7, 8):
                    cell.setTextAlignment(Qt.AlignmentFlag.AlignRight | Qt.AlignmentFlag.AlignVCenter)
                else:
                    cell.setTextAlignment(Qt.AlignmentFlag.AlignLeft | Qt.AlignmentFlag.AlignVCenter)
                self.table.setItem(row, col, cell)

            sess_id = str(item.get("session_id", ""))
            is_active = (sess_id == self._active_session_id and bool(sess_id))
            action_widget = _table_action_button(
                "Viewing" if is_active else "Preview",
                "previewTableBtn",
                lambda _=None, s=sess_id: self.preview_session(s),
                active=is_active,
            )
            self.table.setCellWidget(row, 9, action_widget)

        self._block_table_signals = False

        # 2. Populate Topic Group Cards
        # Clear existing topic cards
        for card in self._topic_cards:
            self.topic_layout.removeWidget(card)
            card.deleteLater()
        self._topic_cards.clear()

        # Group visible sessions by topic
        grouped: dict[str, list[dict[str, Any]]] = {}
        for s in self._visible:
            t = str(s.get("topic") or "General").strip()
            grouped.setdefault(t, []).append(s)

        for topic_name, topic_sessions in grouped.items():
            card = TopicCard(topic_name, topic_sessions, self.topic_container)
            card.selection_changed.connect(self._on_topic_card_selection_changed)
            card.preview_requested.connect(self.preview_session)
            if self._active_session_id:
                card.set_active_preview(self._active_session_id)
            self._topic_cards.append(card)
            # Insert before the stretch
            self.topic_layout.insertWidget(self.topic_layout.count() - 1, card)

        self._update_action_counts()

    def preview_session(self, session_id: str) -> None:
        if not session_id:
            return
        if self.preview_drawer.isVisible() and self._active_session_id == session_id:
            self.preview_drawer.hide()
            self._set_active_preview("")
            return

        self._set_active_preview(session_id)
        self.preview_drawer.load_session(session_id)
        self.preview_drawer.show()

    def _on_preview_closed(self) -> None:
        self._set_active_preview("")

    def _set_active_preview(self, session_id: str) -> None:
        self._active_session_id = session_id
        for card in self._topic_cards:
            card.set_active_preview(session_id)
        self._update_flat_table_preview_active()

    def _update_flat_table_preview_active(self) -> None:
        for row in range(self.table.rowCount()):
            if row < len(self._visible):
                sess = self._visible[row]
                sess_id = str(sess.get("session_id", ""))
                is_active = (sess_id == self._active_session_id and bool(sess_id))
                action_widget = _table_action_button(
                    "Viewing" if is_active else "Preview",
                    "previewTableBtn",
                    lambda _=None, s=sess_id: self.preview_session(s),
                    active=is_active,
                )
                self.table.setCellWidget(row, 9, action_widget)

    def _on_table_item_changed(self, item: QTableWidgetItem) -> None:
        if self._block_table_signals:
            return
        if item.column() == 0:
            is_checked = (
                item.checkState() in (Qt.CheckState.Checked, Qt.CheckState.Checked.value, 2)
                or item.data(Qt.ItemDataRole.CheckStateRole) in (Qt.CheckState.Checked, Qt.CheckState.Checked.value, 2)
            )
            bg_color = QColor("#f0fdfa") if is_checked else QColor("#ffffff")
            for col in range(self.table.columnCount()):
                it = self.table.item(item.row(), col)
                if it is not None:
                    it.setBackground(bg_color)
            self._update_action_counts()

    def _on_topic_card_selection_changed(self) -> None:
        self._update_action_counts()

    def _update_action_counts(self) -> None:
        count = len(self._get_selected_sessions())
        if count > 0:
            self.export_button.setText(f"Export CSV ({count})")
            self.delete_button.setText(f"Delete ({count})")
        else:
            self.export_button.setText("Export selected CSV(s)")
            self.delete_button.setText("Delete selected")

    def _select_all(self) -> None:
        # Select all topic cards
        for card in self._topic_cards:
            card.select_all(True)

        # Select all rows in flat table
        self._block_table_signals = True
        for row in range(self.table.rowCount()):
            item = self.table.item(row, 0)
            if item is not None:
                item.setCheckState(Qt.CheckState.Checked)
            for col in range(self.table.columnCount()):
                it = self.table.item(row, col)
                if it is not None:
                    it.setBackground(QColor("#f0fdfa"))
        self._block_table_signals = False
        self._update_action_counts()

    def _deselect_all(self) -> None:
        for card in self._topic_cards:
            card.select_all(False)

        self._block_table_signals = True
        for row in range(self.table.rowCount()):
            item = self.table.item(row, 0)
            if item is not None:
                item.setCheckState(Qt.CheckState.Unchecked)
            for col in range(self.table.columnCount()):
                it = self.table.item(row, col)
                if it is not None:
                    it.setBackground(QColor("#ffffff"))
        self._block_table_signals = False
        self._update_action_counts()

    def _get_selected_sessions(self) -> list[dict[str, Any]]:
        # Collect from topic cards if in topic view
        card_selected = []
        for card in self._topic_cards:
            card_selected.extend(card.get_selected_sessions())

        table_checked = []
        for row in range(self.table.rowCount()):
            item = self.table.item(row, 0)
            if item is not None:
                is_checked = (
                    item.checkState() in (Qt.CheckState.Checked, Qt.CheckState.Checked.value, 2)
                    or item.data(Qt.ItemDataRole.CheckStateRole) in (Qt.CheckState.Checked, Qt.CheckState.Checked.value, 2)
                )
                if is_checked and row < len(self._visible):
                    table_checked.append(self._visible[row])

        # Merge unique sessions by session_id
        merged = {}
        for s in card_selected + table_checked:
            sid = s.get("session_id") or id(s)
            merged[sid] = s
        if merged:
            return list(merged.values())

        # Fallback to selected rows in table
        selected_rows = {index.row() for index in self.table.selectedIndexes()}
        return [self._visible[r] for r in sorted(selected_rows) if r < len(self._visible)]

    def _change_folder(self) -> None:
        current_dir = self.controller.state.journal_root or str(Path.home() / "Documents" / "WheelAthlete" / "PC Sessions")
        chosen = QFileDialog.getExistingDirectory(self, "Select Session Storage Folder", current_dir)
        if chosen:
            self.controller.set_session_folder(chosen)

    def _open_folder(self) -> None:
        root = self.controller.state.journal_root or str(Path.home() / "Documents" / "WheelAthlete" / "PC Sessions")
        if root and Path(root).exists():
            QDesktopServices.openUrl(QUrl.fromLocalFile(root))
        else:
            _show_info_dialog(self, "Session Folder", f"Folder does not exist yet:\n\n{root}")

    def _export_selected(self) -> None:
        selected = self._get_selected_sessions()
        if not selected:
            _show_info_dialog(
                self, "Export CSV", "Please select or check at least one recording to export."
            )
            return

        default_dir = str(Path.home() / "Documents" / "WheelAthlete" / "Exports")
        chosen_dir = QFileDialog.getExistingDirectory(
            self, "Select Directory for CSV Export", default_dir
        )
        if not chosen_dir:
            return

        exported = self.controller.export_sessions(selected, chosen_dir)
        _show_info_dialog(
            self,
            "Export Complete",
            f"Successfully exported {len(exported)} session CSV(s) organized by topic folders to:\n\n{chosen_dir}",
        )

    def _delete_selected(self) -> None:
        selected = self._get_selected_sessions()
        if not selected:
            _show_info_dialog(
                self, "Delete Recording", "Please select or check at least one recording to delete."
            )
            return

        session_ids = [str(s.get("session_id", "")) for s in selected if s.get("session_id")]
        confirmed = _ask_confirm_dialog(
            self,
            "Delete recordings",
            f"Delete {len(session_ids)} recording(s) and their raw research data?\n\nThis action cannot be undone.",
            confirm_text="Yes, Delete",
            cancel_text="Cancel",
            danger=True,
        )
        if confirmed:
            self.controller.delete_sessions(session_ids)


SessionsPage = ResultsPage


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
        self.acquisition = AcquisitionPage(controller)
        self.live = self.acquisition
        self.record = self.acquisition
        self.results = ResultsPage(controller)
        self.sessions = self.results
        self.diagnostics = DiagnosticsPage(controller)
        for page in (self.dashboard, self.acquisition, self.results, self.diagnostics):
            self.stack.addWidget(page)
        content_layout.addWidget(self.stack, 1)
        layout.addWidget(content, 1)

        self.nav.currentRowChanged.connect(self.stack.setCurrentIndex)
        controller.state_changed.connect(self._update_header)
        controller.message.connect(self._show_message)
        controller.command_error.connect(self._show_error)
        controller.sessions_changed.connect(self.results.update_sessions)
        self._update_header(controller.state)

        toggle_action = QAction("Toggle fullscreen", self)
        toggle_action.setShortcut("F11")
        toggle_action.triggered.connect(lambda: self.showNormal() if self.isFullScreen() else self.showFullScreen())
        self.addAction(toggle_action)

    def start(self) -> None:
        self.controller.start()

    def _update_header(self, state: AppViewState) -> None:
        self.daemon_badge.setText("DAQ READY" if state.daemon_connected else "Daemon offline")
        self.daemon_badge.setProperty("online", state.daemon_connected)
        self.daemon_badge.style().unpolish(self.daemon_badge)
        self.daemon_badge.style().polish(self.daemon_badge)
        self.record_badge.setText(
            "RECORDING"
            if state.recording
            else "COUNTDOWN"
            if state.recording_starting
            else "LIVE"
            if state.live
            else "IDLE"
        )
        self.record_badge.setProperty("recording", state.recording)
        self.record_badge.setProperty("live", state.live and not state.recording)
        self.record_badge.style().unpolish(self.record_badge)
        self.record_badge.style().polish(self.record_badge)
        self.session_label.setText(f"Session {state.session_id}" if state.session_id else "")

    def _show_message(self, text: str) -> None:
        self.statusBar().showMessage(text, 5000)

    def _show_error(self, command: str, message: str) -> None:
        self.statusBar().showMessage(f"{command}: {message}", 8000)

    def closeEvent(self, event: QCloseEvent) -> None:
        if (
            self.controller.state.recording
            or self.controller.state.recording_starting
        ) and not self.demo:
            confirmed = _ask_confirm_dialog(
                self,
                "Recording is still active",
                "Close only the UI and leave the acquisition daemon recording?\n\nRaw data will continue to be owned by the daemon.",
                confirm_text="Yes, Close UI",
                cancel_text="Cancel",
                danger=True,
            )
            if not confirmed:
                event.ignore()
                return
        self.controller.close()
        event.accept()
