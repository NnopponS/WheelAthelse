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


def test_ready_state_triggers_interactive_installer_and_app_exit(monkeypatch) -> None:
    controller = DemoController()
    window = MainWindow(controller, demo=True)
    installed_args = []
    quitted = []

    monkeypatch.setattr(
        window.update_controller,
        "install",
        lambda *, silent=False: installed_args.append(silent),
    )
    monkeypatch.setattr(QApplication, "quit", lambda: quitted.append(True))

    window._update_update_ui(
        UpdateViewState(
            status="ready",
            current_version="1.8.0",
            available_version="1.8.1",
            message="Update verified and ready to install",
        )
    )
    window._apply_downloaded_update()
    assert installed_args == [False]  # silent=False so setup GUI appears
    assert quitted == [True]
    assert window._installing_update is True

    window.close()
    window.deleteLater()
    _APP.processEvents()

