import os

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PySide6.QtWidgets import QApplication, QCheckBox, QDialog, QMessageBox

from tools.pc_gui import main_window
from tools.pc_gui.controller import DemoController
from tools.pc_gui.main_window import MainWindow


_APP = QApplication.instance() or QApplication([])


def test_cleanup_choices_default_off_and_cancelled_confirmation_does_not_delete(monkeypatch, tmp_path):
    portable_root = tmp_path / "WheelAthlete"
    monkeypatch.setattr(
        main_window,
        "portable_application_root",
        lambda *_args, **_kwargs: portable_root,
    )
    seen = {}

    class InspectingDialog(QDialog):
        def exec(self):
            data = self.findChild(QCheckBox, "deleteWheelAthleteDataCheck")
            app = self.findChild(QCheckBox, "removePortableAppCheck")
            seen["defaults"] = (data.isChecked(), app.isChecked())
            data.setChecked(True)
            return QDialog.DialogCode.Accepted

    class RejectCleanup:
        StandardButton = QMessageBox.StandardButton

        @staticmethod
        def warning(*_args, **_kwargs):
            return QMessageBox.StandardButton.No

    monkeypatch.setattr(main_window, "QDialog", InspectingDialog)
    monkeypatch.setattr(main_window, "QMessageBox", RejectCleanup)
    controller = DemoController()
    window = MainWindow(controller, demo=True)
    close_calls = []
    window.close = lambda: close_calls.append(True)

    window._cleanup_action()

    assert seen["defaults"] == (False, False)
    assert window._pending_cleanup is None
    assert close_calls == []
    window.deleteLater()
