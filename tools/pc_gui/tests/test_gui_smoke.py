import os
from pathlib import Path
import tempfile
from PySide6.QtCore import Qt
from PySide6.QtWidgets import QApplication, QAbstractItemView, QFrame, QLineEdit, QMessageBox, QPushButton

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from tools.pc_gui.controller import DemoController
from tools.pc_gui.main_window import MainWindow


_APP = QApplication.instance() or QApplication([])


def test_python_research_ui_navigation_and_combined_acquisition():
    controller = DemoController()
    window = MainWindow(controller, demo=True)
    window.show()
    window.start()
    _APP.processEvents()

    # 5 clean pages: Dashboard, Acquisition, Results, MODEL, Diagnostics
    assert window.nav.count() == 5
    assert window.stack.count() == 5
    assert window.windowTitle() == "WheelAthlete — Python Research Edition"
    assert window.daemon_badge.text() == "DAQ READY"

    assert window.dashboard.devices.verticalHeader().isHidden()
    assert (
        window.dashboard.devices.editTriggers()
        == QAbstractItemView.EditTrigger.NoEditTriggers
    )
    assert "QTableWidget::item:selected" in window.styleSheet()
    assert "QComboBox QAbstractItemView" in window.styleSheet()

    # Combined acquisition page: Live preview toggle
    window.acquisition.live_button.click()
    _APP.processEvents()
    assert controller.state.live
    assert window.acquisition.live_button.text() == "Stop live preview"
    window.acquisition.live_button.click()
    _APP.processEvents()
    assert not controller.state.live

    # Live telemetry cards render on the same page
    window.acquisition._render.stop()
    controller._timer.stop()
    controller._tick()
    window.acquisition.render()
    _APP.processEvents()
    assert window.acquisition.current["L"].values["ax"].value.text() != "—"
    assert window.acquisition.current["R"].values["gz"].value.text() != "—"
    assert window.acquisition.trial.text() == "1"
    assert window.acquisition.accel_chart_l.view.frameShape() == QFrame.Shape.NoFrame
    assert (
        window.acquisition.accel_chart_l.view.backgroundBrush().color().name()
        == "#ffffff"
    )

    # Dashboard settings configuration
    window.dashboard.settings_rate.setCurrentText("200 Hz")
    window.dashboard.settings_accel.setCurrentIndex(2)
    window.dashboard.settings_gyro.setCurrentIndex(1)
    window.dashboard._apply_settings(("L",))
    assert controller.state.boards["L"].configured_rate_hz == 200
    assert controller.state.boards["L"].accel_range == 2
    assert controller.state.boards["L"].gyro_range == 1
    assert controller.state.boards["L"].accel_scale == 8 / 32768
    assert controller.state.boards["L"].gyro_scale == 500 / 32768

    # Start record directly on the same acquisition screen with form metadata
    window.acquisition.athlete.setText("TestRunner")
    window.acquisition.topic.setText("Sprint")
    window.acquisition.trial.setValue(3)
    controller.start_record(window.acquisition.metadata())
    _APP.processEvents()
    assert controller.state.recording
    assert not window.acquisition.stop_button.isHidden()
    assert window.acquisition.start_button.isHidden()

    controller.stop_record()
    _APP.processEvents()
    assert not controller.state.recording
    assert "Final QC: GOOD" in window.acquisition.result_title.text()

    controller.close()
    window.close()
    window.deleteLater()
    _APP.processEvents()


def test_results_page_batch_export_and_session_folder():
    controller = DemoController()
    window = MainWindow(controller, demo=True)
    window.show()
    window.start()
    _APP.processEvents()

    results = window.results
    assert results.table.rowCount() >= 2
    assert results.table.columnWidth(9) >= 110
    assert results._topic_cards[0].table.columnWidth(8) >= 110
    assert results.topic_filter.count() >= 2
    assert len(results._topic_cards) >= 1

    # Test filtering by topic
    results.topic_filter.setCurrentText("Sprint")
    _APP.processEvents()
    for row in range(results.table.rowCount()):
        assert results.table.item(row, 2).text() == "Sprint"

    # Test Select All and Row Highlighting
    results.select_all_btn.click()
    _APP.processEvents()
    for row in range(results.table.rowCount()):
        assert results.table.item(row, 0).checkState() == Qt.CheckState.Checked
        # Highlighted background color check
        bg = results.table.item(row, 0).background().color()
        assert bg.name() == "#f0fdfa"

    selected = results._get_selected_sessions()
    assert len(selected) > 0

    # Test batch export to temporary folder creating Topic_trial_athlete naming
    with tempfile.TemporaryDirectory() as tmpdir:
        exported = controller.export_sessions(selected, tmpdir)
        assert len(exported) == len(selected)
        for path_str in exported:
            p = Path(path_str)
            assert p.exists()
            assert p.suffix == ".csv"
            # Must be placed in a topic folder
            assert p.parent.name == "Sprint"
            # Must follow Topic_Trial#_Athlete naming
            assert p.stem.startswith("Sprint_Trial")
            assert "Athlete" in p.stem or "Sprint" in p.stem

    # Test Deselect All
    results.deselect_all_btn.click()
    _APP.processEvents()
    assert len(results._get_selected_sessions()) == 0
    assert results.delete_button.text() == "Delete selected"

    # Test individual checkbox toggle in table
    item0 = results.table.item(0, 0)
    item0.setCheckState(Qt.CheckState.Checked)
    _APP.processEvents()
    assert len(results._get_selected_sessions()) == 1
    assert results.delete_button.text() == "Delete (1)"
    assert results.export_button.text() == "Export CSV (1)"

    # Test changing session folder
    with tempfile.TemporaryDirectory() as custom_folder:
        controller.set_session_folder(custom_folder)
        assert controller.state.journal_root == custom_folder
        assert results.folder_label.text() == custom_folder

    controller.close()
    window.close()
    window.deleteLater()
    _APP.processEvents()


def test_results_topic_grouping_see_more_and_telemetry_preview():
    controller = DemoController()
    window = MainWindow(controller, demo=True)
    window.show()
    window.start()
    # Switch to Results page (index 2)
    window.stack.setCurrentIndex(2)
    _APP.processEvents()

    results = window.results
    assert len(results._topic_cards) >= 1

    card = results._topic_cards[0]
    assert card.table_container.isHidden()
    assert "View Trials" in card.toggle_btn.text()
    assert "Athletes:" in card.athletes_pill.text()

    # Click "View Trials" to expand trials table
    card.toggle_btn.click()
    _APP.processEvents()
    assert not card.table_container.isHidden()
    assert card.toggle_btn.text() == "Hide Trials"
    assert card.table.minimumHeight() < 380

    # Test topic-level checkbox selection
    card.check.setChecked(True)
    _APP.processEvents()
    for r in range(card.table.rowCount()):
        assert card.table.item(r, 0).checkState() == Qt.CheckState.Checked
        assert card.table.item(r, 0).background().color().name() == "#f0fdfa"

    # Inline rename: there is no Edit button. Trial/Athlete cells are edited
    # directly by double-click, independent from batch checkbox state.
    first_actions = card.table.cellWidget(0, 8)
    assert first_actions is not None
    assert first_actions.findChild(QPushButton, "editTableBtn") is None
    row_preview = first_actions.findChild(QPushButton, "previewTableBtn")
    assert row_preview is not None and row_preview.text() == "Preview"
    assert card.table.editTriggers() & QAbstractItemView.EditTrigger.DoubleClicked
    assert card.table.item(0, 2).flags() & Qt.ItemFlag.ItemIsEditable
    assert card.table.item(0, 3).flags() & Qt.ItemFlag.ItemIsEditable
    assert not (card.table.item(0, 1).flags() & Qt.ItemFlag.ItemIsEditable)

    # Test Telemetry Preview Drawer (Lossless session)
    results.preview_session("demo_sprint_01")
    _APP.processEvents()
    assert not results.preview_drawer.isHidden()
    assert "Lossless" in results.preview_drawer.integrity_badge.text()
    assert results.preview_drawer.accel_series["L_X"].count() > 0

    # Regression: clicking the active preview again must not hide the drawer or
    # replace/delete the cell action widget that emitted the click.
    active_card = next(c for c in results._topic_cards if c.topic == "Sprint")
    active_row = next(
        i for i, s in enumerate(active_card.sessions)
        if s.get("session_id") == "demo_sprint_01"
    )
    action_container = active_card.table.cellWidget(active_row, 8)
    assert action_container is not None
    action_button = action_container.findChild(QPushButton)
    assert action_button is not None
    assert action_button.text() == "Viewing"
    results.preview_session("demo_sprint_01")
    _APP.processEvents()
    assert not results.preview_drawer.isHidden()
    assert active_card.table.cellWidget(active_row, 8) is action_container
    assert action_button.text() == "Viewing"

    # Test Telemetry Preview Drawer (Session with Signal Loss gap)
    results.preview_session("demo_sprint_02")
    _APP.processEvents()
    assert "Signal Loss" in results.preview_drawer.integrity_badge.text()
    assert results.preview_drawer.accel_gap_scatter.count() > 0

    # Test close preview drawer
    results.preview_drawer.close_btn.click()
    _APP.processEvents()
    assert results.preview_drawer.isHidden()

    controller.close()
    window.close()
    window.deleteLater()
    _APP.processEvents()


def test_results_inline_metadata_editing_has_no_edit_buttons(monkeypatch):
    controller = DemoController()
    window = MainWindow(controller, demo=True)
    window.show()
    window.start()
    window.stack.setCurrentIndex(2)
    _APP.processEvents()

    results = window.results
    assert not hasattr(results, "edit_button")

    # Flat table exposes all user-facing rename fields directly without Qt row
    # selection; checkbox state owns batch selection so Preview must never be
    # covered by the dark selected-row overlay while editing.
    assert results.table.editTriggers() & QAbstractItemView.EditTrigger.DoubleClicked
    assert results.table.selectionMode() == QAbstractItemView.SelectionMode.NoSelection
    results.view_tabs.setCurrentIndex(1)
    results.table.setCurrentCell(0, 4)
    _APP.processEvents()
    assert results.table.selectedItems() == []
    preview_container = results.table.cellWidget(0, 9)
    assert preview_container is not None
    preview_button = preview_container.findChild(QPushButton, "previewTableBtn")
    assert preview_button is not None and preview_button.isVisible()
    assert results.table.item(0, 2).flags() & Qt.ItemFlag.ItemIsEditable  # Topic
    assert results.table.item(0, 3).flags() & Qt.ItemFlag.ItemIsEditable  # Trial
    assert results.table.item(0, 4).flags() & Qt.ItemFlag.ItemIsEditable  # Athlete
    assert not (results.table.item(0, 1).flags() & Qt.ItemFlag.ItemIsEditable)  # Quality

    session_id = str(results._visible[0]["session_id"])
    monkeypatch.setattr(
        QMessageBox,
        "question",
        lambda *args, **kwargs: QMessageBox.StandardButton.Yes,
    )
    results.table.item(0, 4).setText("Inline Athlete")
    _APP.processEvents()
    updated = next(s for s in controller.sessions if s.get("session_id") == session_id)
    assert updated["athlete"] == "Inline Athlete"

    # Grouped view still supports direct Trial/Athlete editing and retains only Preview.
    grouped = next(c for c in results._topic_cards if any(s.get("session_id") == session_id for s in c.sessions))
    grouped_row = next(i for i, s in enumerate(grouped.sessions) if s.get("session_id") == session_id)
    actions = grouped.table.cellWidget(grouped_row, 8)
    assert actions is not None
    assert actions.findChild(QPushButton, "editTableBtn") is None
    assert actions.findChild(QPushButton, "previewTableBtn") is not None

    controller.close()
    window.close()
    window.deleteLater()
    _APP.processEvents()



def test_inline_metadata_edit_requires_confirmation(monkeypatch):
    controller = DemoController()
    window = MainWindow(controller, demo=True)
    window.show()
    window.start()
    window.stack.setCurrentIndex(2)
    _APP.processEvents()

    results = window.results
    session_id = str(results._visible[0]["session_id"])
    old_athlete = str(results._visible[0].get("athlete") or "")

    monkeypatch.setattr(
        QMessageBox,
        "question",
        lambda *args, **kwargs: QMessageBox.StandardButton.No,
    )
    results.table.item(0, 4).setText("Should Not Save")
    _APP.processEvents()
    _APP.processEvents()
    unchanged = next(s for s in controller.sessions if s.get("session_id") == session_id)
    assert unchanged["athlete"] == old_athlete

    monkeypatch.setattr(
        QMessageBox,
        "question",
        lambda *args, **kwargs: QMessageBox.StandardButton.Yes,
    )
    row = next(i for i, s in enumerate(results._visible) if s.get("session_id") == session_id)
    results.table.item(row, 4).setText("Confirmed Athlete")
    _APP.processEvents()
    changed = next(s for s in controller.sessions if s.get("session_id") == session_id)
    assert changed["athlete"] == "Confirmed Athlete"

    controller.close()
    window.close()
    window.deleteLater()
    _APP.processEvents()


def test_group_name_can_be_renamed_with_confirmation(monkeypatch):
    controller = DemoController()
    window = MainWindow(controller, demo=True)
    window.show()
    window.start()
    window.stack.setCurrentIndex(2)
    _APP.processEvents()

    results = window.results
    card = next(c for c in results._topic_cards if c.topic == "Sprint")
    assert isinstance(card.title_label, QLineEdit)
    assert card.title_label.isReadOnly()
    assert "Double-click" in card.title_label.toolTip()

    monkeypatch.setattr(
        QMessageBox,
        "question",
        lambda *args, **kwargs: QMessageBox.StandardButton.No,
    )
    card.topic_rename_requested.emit("Sprint", "Sprint Cancelled")
    _APP.processEvents()
    _APP.processEvents()
    assert any((s.get("topic") or "") == "Sprint" for s in controller.sessions)
    assert not any((s.get("topic") or "") == "Sprint Cancelled" for s in controller.sessions)

    monkeypatch.setattr(
        QMessageBox,
        "question",
        lambda *args, **kwargs: QMessageBox.StandardButton.Yes,
    )
    current = next(c for c in results._topic_cards if c.topic == "Sprint")
    current.topic_rename_requested.emit("Sprint", "Sprint Renamed")
    _APP.processEvents()
    _APP.processEvents()
    assert not any((s.get("topic") or "") == "Sprint" for s in controller.sessions)
    assert any((s.get("topic") or "") == "Sprint Renamed" for s in controller.sessions)

    controller.close()
    window.close()
    window.deleteLater()
    _APP.processEvents()
