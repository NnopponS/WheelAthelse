import os

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PySide6.QtWidgets import QApplication

from tools.pc_gui.controller import DemoController
from tools.pc_gui.main_window import MainWindow


_APP = QApplication.instance() or QApplication([])


def test_python_research_ui_exposes_simple_six_page_navigation_and_live_values():
    controller = DemoController()
    window = MainWindow(controller, demo=True)
    window.show()
    window.start()
    _APP.processEvents()

    assert window.nav.count() == 6
    assert window.stack.count() == 6
    assert window.windowTitle() == "WheelAthlete — Python Research Edition"
    assert window.daemon_badge.text() == "DAQ READY"

    window.live._render.stop()
    controller._timer.stop()
    controller._tick()
    window.live.render()
    _APP.processEvents()
    assert window.live.current["L"].values["ax"].value.text() != "—"
    assert window.live.current["R"].values["gz"].value.text() != "—"

    window.dashboard.settings_rate.setCurrentText("200 Hz")
    window.dashboard.settings_accel.setCurrentIndex(2)
    window.dashboard.settings_gyro.setCurrentIndex(1)
    window.dashboard._apply_settings(("L",))
    assert controller.state.boards["L"].configured_rate_hz == 200
    assert controller.state.boards["L"].accel_range == 2
    assert controller.state.boards["L"].gyro_range == 1
    assert controller.state.boards["L"].accel_scale == 8 / 32768
    assert controller.state.boards["L"].gyro_scale == 500 / 32768

    controller.start_record({"sample_rate_hz": 100})
    _APP.processEvents()
    assert controller.state.recording
    # The Record page is not the current stacked page in this test, so
    # QWidget.isVisible() would be false even though the button itself was
    # switched from hidden to shown by the recording state.
    assert not window.record.stop_button.isHidden()
    assert window.record.start_button.isHidden()

    controller.stop_record()
    _APP.processEvents()
    assert not controller.state.recording
    assert "Final QC: GOOD" in window.record.result_title.text()

    controller.close()
    window.close()
    window.deleteLater()
    _APP.processEvents()
