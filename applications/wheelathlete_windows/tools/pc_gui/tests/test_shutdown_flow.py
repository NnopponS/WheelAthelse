import os

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PySide6.QtGui import QCloseEvent
from PySide6.QtWidgets import QApplication, QMessageBox

from tools.pc_gui import main_window
from tools.pc_gui.controller import DemoController
from tools.pc_gui.main_window import MainWindow


_APP = QApplication.instance() or QApplication([])


class _CloseController(DemoController):
    def __init__(self):
        super().__init__()
        self.state.daemon_connected = True
        self.stop_calls = 0
        self.shutdown_calls = 0
        self.close_calls = 0

    def stop_record(self):
        self.stop_calls += 1
        self.state.recording = False
        self.state.recording_starting = False
        self.state_changed.emit(self.state)
        self.recording_finished.emit({"finalized": True})

    def shutdown_daemon(self):
        self.shutdown_calls += 1

    def close(self):
        self.close_calls += 1


def test_closing_active_recording_stops_finalizes_then_waits_for_daemon_ack(monkeypatch):
    controller = _CloseController()
    controller.state.recording = True
    window = MainWindow(controller, demo=False)
    monkeypatch.setattr(main_window, "_ask_confirm_dialog", lambda *a, **k: True)
    event = QCloseEvent()

    window.closeEvent(event)

    assert not event.isAccepted()
    assert controller.stop_calls == 1
    assert controller.shutdown_calls == 1
    assert controller.close_calls == 0

    controller.shutdown_completed.emit()
    assert controller.close_calls == 1
    window.deleteLater()


def test_closing_idle_window_waits_for_shutdown_ack(monkeypatch):
    controller = _CloseController()
    window = MainWindow(controller, demo=False)
    monkeypatch.setattr(QMessageBox, "critical", lambda *a, **k: QMessageBox.StandardButton.Ok)
    event = QCloseEvent()

    window.closeEvent(event)

    assert not event.isAccepted()
    assert controller.shutdown_calls == 1
    assert controller.close_calls == 0

    controller.shutdown_completed.emit()
    assert controller.close_calls == 1
    window.deleteLater()


def test_shutdown_failure_keeps_window_open(monkeypatch):
    controller = _CloseController()
    window = MainWindow(controller, demo=False)
    monkeypatch.setattr(QMessageBox, "critical", lambda *a, **k: QMessageBox.StandardButton.Ok)
    event = QCloseEvent()

    window.closeEvent(event)
    controller.shutdown_failed.emit("failed to stop")

    assert not event.isAccepted()
    assert controller.close_calls == 0
    assert not window._shutdown_pending
    window.deleteLater()
