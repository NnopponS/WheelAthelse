import os

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PySide6.QtWidgets import QApplication

from tools.pc_gui.controller import DemoController
from tools.pc_gui.main_window import MainWindow
from tools.pc_gui.update_controller import UpdateViewState


_APP = QApplication.instance() or QApplication([])


def test_update_button_exists_and_reflects_available_release() -> None:
    controller = DemoController()
    window = MainWindow(controller, demo=True)
    window.show()
    _APP.processEvents()

    assert window.update_button.accessibleName() == "softwareUpdateButton"
    assert window.update_button.text() == "Check updates"

    window._update_update_ui(
        UpdateViewState(
            status="available",
            current_version="1.8.0",
            available_version="1.8.1",
            message="WheelAthlete 1.8.1 is available",
            install_supported=False,
        )
    )
    assert window.update_button.text() == "Update to 1.8.1"
    assert "1.8.1" in window.update_button.toolTip()

    window.close()
    window.deleteLater()
    _APP.processEvents()


def test_source_mode_does_not_start_background_update_timer() -> None:
    controller = DemoController()
    window = MainWindow(controller, demo=True)
    assert not window.update_controller.state.install_supported
    window.start()
    _APP.processEvents()
    assert not window.update_controller._timer.isActive()
    window.close()
    window.deleteLater()
    _APP.processEvents()
