import os

from PySide6.QtWidgets import QApplication, QLabel

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from tools.pc_gui.controller import DemoController
from tools.pc_gui.main_window import MainWindow


_APP = QApplication.instance() or QApplication([])


def test_results_are_date_first_above_topic_groups():
    controller = DemoController()
    window = MainWindow(controller, demo=True)
    window.show()
    window.start()
    _APP.processEvents()

    assert window.results.view_tabs.tabText(0) == "Date / Topic"
    assert len(window.results._date_headers) >= 2
    labels = [header.findChild(QLabel, "dateTitle") for header in window.results._date_headers]
    assert all(label is not None and label.text() for label in labels)
    assert len(window.results._topic_cards) >= 2

    controller.close()
    window.close()
    window.deleteLater()
    _APP.processEvents()


def test_recording_clock_displays_elapsed_seconds_without_utc():
    controller = DemoController()
    window = MainWindow(controller, demo=True)
    window.show()
    window.start()
    _APP.processEvents()

    controller.start_record({"sample_rate_hz": 100})
    _APP.processEvents()
    window.acquisition._update_record_clock()
    text = window.acquisition.countdown_label.text()
    assert text.startswith("Recording ")
    assert text.endswith(" s")
    assert "UTC" not in text
    assert controller.state.recording_started_utc_ms is not None

    controller.stop_record()
    _APP.processEvents()
    assert controller.state.recording_started_utc_ms is None

    controller.close()
    window.close()
    window.deleteLater()
    _APP.processEvents()
