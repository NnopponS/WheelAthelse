import os
from datetime import datetime, timedelta

from PySide6.QtWidgets import QApplication, QLabel

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from tools.pc_gui.controller import DemoController
from tools.pc_gui.main_window import MainWindow, _session_date_bucket


_APP = QApplication.instance() or QApplication([])


def test_results_are_date_first_above_topic_groups():
    controller = DemoController()
    window = MainWindow(controller, demo=True)
    window.show()
    window.start()
    _APP.processEvents()

    assert window.results.view_tabs.tabText(0) == "Day / Experiment"
    assert len(window.results._date_headers) >= 2
    labels = [header.findChild(QLabel, "dateTitle") for header in window.results._date_headers]
    assert all(label is not None and label.text() for label in labels)
    assert len(window.results._topic_cards) >= 2

    controller.close()
    window.close()
    window.deleteLater()
    _APP.processEvents()


def test_results_selection_persists_across_filters_and_supports_day_or_all():
    controller = DemoController()
    window = MainWindow(controller, demo=True)
    window.show()
    window.start()
    _APP.processEvents()

    results = window.results
    newest_day = max(_session_date_bucket(item)[0] for item in controller.sessions)
    results._select_day(newest_day)
    assert {item["session_id"] for item in results._get_selected_sessions()} == {
        "demo_sprint_01",
        "demo_sprint_02",
    }

    results.search.setText("Endurance")
    _APP.processEvents()
    assert len(results._visible) == 1
    assert len(results._get_selected_sessions()) == 2

    results._select_all()
    assert len(results._get_selected_sessions()) == 3
    assert "3 recording(s) selected" in results.selection_summary.text()
    results._deselect_all()
    assert results._get_selected_sessions() == []

    results.search.clear()
    results._toggle_day(newest_day)
    assert newest_day in results._collapsed_days
    assert all(
        not card.isVisible()
        for card in results._topic_cards
        if _session_date_bucket(card.sessions[0])[0] == newest_day
    )

    controller.close()
    window.close()
    window.deleteLater()
    _APP.processEvents()


def test_results_deduplicate_ids_and_group_by_local_midnight():
    controller = DemoController()
    window = MainWindow(controller, demo=True)
    window.show()
    window.start()
    _APP.processEvents()

    local_zone = datetime.now().astimezone().tzinfo
    before = datetime(2026, 9, 8, 23, 59, tzinfo=local_zone)
    after = before + timedelta(minutes=2)
    sessions = [
        {
            **controller.sessions[0],
            "session_id": "same",
            "started_utc_ms": int(before.timestamp() * 1000),
            "recorded_utc_ms": int(before.timestamp() * 1000),
        },
        {
            **controller.sessions[1],
            "session_id": "same",
            "started_utc_ms": int(after.timestamp() * 1000),
            "recorded_utc_ms": int(after.timestamp() * 1000),
        },
        {
            **controller.sessions[2],
            "session_id": "next",
            "started_utc_ms": int(after.timestamp() * 1000),
            "recorded_utc_ms": int(after.timestamp() * 1000),
        },
    ]
    window.results.update_sessions(sessions)
    assert len(window.results._sessions) == 2
    assert _session_date_bucket(sessions[0])[0] != _session_date_bucket(sessions[1])[0]
    window.results._select_all()
    assert {item["session_id"] for item in window.results._get_selected_sessions()} == {
        "same",
        "next",
    }

    window.results.update_sessions([])
    assert window.results._get_selected_sessions() == []
    assert window.results.selection_summary.text() == "No recordings selected"

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
