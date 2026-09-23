import os
from pathlib import Path

import pytest
from PySide6.QtCore import Qt
from PySide6.QtWidgets import QApplication

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault(
    "WHEELATHLETE_MODEL_DIR",
    str(Path(__file__).resolve().parent / "_empty_model_library"),
)

from tools.pc_gui.controller import DemoController
from tools.pc_gui.analysis_contract import build_analysis
from tools.pc_gui.main_window import MainWindow


_APP = QApplication.instance() or QApplication([])


def _window() -> tuple[DemoController, MainWindow]:
    controller = DemoController()
    window = MainWindow(controller, demo=True)
    window.resize(1500, 930)
    window.show()
    window.start()
    _APP.processEvents()
    return controller, window


def _close(controller: DemoController, window: MainWindow) -> None:
    controller.close()
    window.close()
    window.deleteLater()
    _APP.processEvents()


def _sample_result(*, net_yaw_deg: float | None = 12.5) -> dict:
    return {
        "session_id": "demo_sprint_01",
        "topic": "Sprint",
        "trial_number": 1,
        "recording_label": "Sprint Â· Trial 1 Â· Test Athlete Â· GOOD",
        "model_label": "BiWheel3D test model",
        "xy": [(0.0, 0.0), (0.5, 0.1), (1.0, 0.4), (1.4, 0.8)],
        "point_count": 4,
        "path_length_m": 1.72,
        "endpoint_m": 1.61,
        "net_yaw_deg": net_yaw_deg,
        "yaw_source": "chassis" if net_yaw_deg is not None else "XY output only",
        "yaw_delay_frames": 27 if net_yaw_deg is not None else 0,
        "preprocess": {
            "aligned_samples": 20,
            "model_steps": 4,
            "warnings": [],
        },
    }


def test_results_selection_can_be_opened_in_model_page():
    controller, window = _window()

    results = window.results
    results._deselect_all()
    item = results.table.item(0, 0)
    item.setCheckState(Qt.CheckState.Checked)
    _APP.processEvents()

    selected = results._get_selected_sessions()
    assert len(selected) == 1
    session_id = str(selected[0]["session_id"])
    assert results.model_button.isEnabled()

    results.model_button.click()
    _APP.processEvents()

    assert window.nav.currentRow() == 3
    assert window.stack.currentWidget() is window.model
    assert str(window.model.session_combo.currentData()) == session_id
    assert window.model.model_combo.count() >= 1
    assert window.model.chart_view.accessibleName() == "trajectoryChart"
    assert window.model.browse_model_button.isVisible()
    assert window.model.browse_model_button.isEnabled()
    assert window.model.browse_research_button.isVisible()
    assert window.model.browse_research_button.isEnabled()

    _close(controller, window)


def test_model_page_renders_trajectory_and_summary_metrics():
    controller, window = _window()
    model = window.model
    window.stack.setCurrentWidget(model)
    _APP.processEvents()

    model._on_analysis_ready(_sample_result())
    _APP.processEvents()
    model._apply_equal_aspect_ranges()

    assert model.trajectory_series.count() == 4
    assert model.start_series.count() == 1
    assert model.end_series.count() == 1
    assert model.metric_points.text() == "4"
    assert model.metric_path.text() == "1.72 m"
    assert model.metric_endpoint.text() == "1.61 m"
    assert model.metric_yaw.text() == "12.5 deg"
    assert model.metric_vertical.text() == "—"
    assert model.metric_session.text() == "Sprint Â· Trial 1 Â· Test Athlete Â· GOOD"
    assert "Sprint" in model.chart.title()
    assert "native 100 Hz" in model.status_label.text()
    assert "Yaw: chassis, delay 27 frame(s)." in model.status_label.text()

    plot = model.chart.plotArea()
    assert plot.width() > 0
    assert plot.height() > 0
    assert plot.width() == pytest.approx(plot.height(), abs=1.0)
    x_span = model.axis_x.max() - model.axis_x.min()
    y_span = model.axis_y.max() - model.axis_y.min()
    assert x_span == pytest.approx(y_span, rel=1e-6)
    x_units_per_px = x_span / plot.width()
    y_units_per_px = y_span / plot.height()
    assert x_units_per_px == pytest.approx(y_units_per_px, rel=0.01)

    model._on_analysis_ready(_sample_result(net_yaw_deg=None))
    assert model.metric_yaw.text() == "\u2014"

    _close(controller, window)


def test_model_page_uses_current_best_and_exposes_model_browser():
    controller, window = _window()
    model = window.model
    _APP.processEvents()

    assert model.model_combo.count() >= 1
    assert model.model_combo.itemText(0) == "Kinematic Trajectory (XY + Yaw)"
    model.model_combo.setCurrentIndex(0)
    _APP.processEvents()
    assert "BiWheel3D-XY-Yaw-current_best.json" in model.model_detail.toolTip()
    assert "recipe ready" in model.runtime_label.text()
    assert "biwheel3d_dual_hub_v1" in model.model_detail.text()
    assert not model.model_detail.isHidden()
    assert not model.runtime_label.isHidden()
    assert not model.browse_model_button.isHidden()
    assert "ONNX" in model.browse_model_button.toolTip()

    _close(controller, window)


def test_model_page_renders_c3d_overlay_for_research_trial():
    controller, window = _window()
    model = window.model
    result = _sample_result()
    result["ground_truth_xy"] = [(0.0, 0.0), (0.45, 0.08), (0.95, 0.35), (1.35, 0.75)]
    result["gt_diagnostic"] = {
        "scope": "full_processed_cache_not_support_masked",
        "ate_rmse_m": 0.082,
        "endpoint_error_m": 0.071,
        "heading_unwrapped_rmse_deg": 4.2,
    }
    model._on_analysis_ready(result)
    _APP.processEvents()
    assert model.ground_truth_series.count() == 4
    assert model.chart.legend().isVisible()
    assert "C3D full-cache diagnostic ATE 0.082 m" in model.status_label.text()
    assert "full-cache diagnostic ATE 0.082 m" in model.status_label.toolTip()
    _close(controller, window)


def test_model_page_opens_orbitable_view_only_for_true_xyz():
    controller, window = _window()
    model = window.model
    result = _sample_result()
    result["xyz"] = [(x, y, z) for (x, y), z in zip(result["xy"], (0.0, 0.2, 0.4, 0.6))]
    model._on_analysis_ready(result)
    assert model.plot_tabs.currentWidget() is model.trajectory_3d_view
    assert model.trajectory_3d_view.has_vertical
    assert model.trajectory_3d_view.points[-1][2] == pytest.approx(0.6)
    assert model.metric_vertical.text() == "0.60 m"

    model._on_analysis_ready(_sample_result())
    assert model.plot_tabs.currentWidget() is model.chart_view
    assert not model.trajectory_3d_view.has_vertical
    assert "Z unavailable" in model.trajectory_3d_view.accessibleDescription()

    model.comp_dual_hub.setChecked(True)
    compared_result = _sample_result()
    compared_result["xyz"] = [
        (x, y, z) for (x, y), z in zip(compared_result["xy"], (0.0, 0.2, 0.4, 0.6))
    ]
    model._on_analysis_ready(compared_result)
    assert model.plot_tabs.currentWidget() is model.chart_view
    _close(controller, window)


def test_invalid_recording_reasons_are_visible_in_results_preview_and_model():
    controller, window = _window()
    session = {
        "session_id": "invalid-demo",
        "topic": "Sprint",
        "trial_number": 1,
        "athlete": "Test Athlete",
        "sample_rate_hz": 100,
        "duration_s": 1.0,
        "quality": "INVALID",
        "sample_counts": {"L": 100, "R": 96, "C": 100},
        "reasons": [
            {"code": "R sequence gaps", "detail": "4,824 samples"}
        ],
    }
    controller.load_session_data = lambda _session_id: {
        **session,
        "samples": {"L": [], "R": [], "C": []},
        "gaps": [],
        "total_missing_samples": 0,
    }
    window.results.update_sessions([session])
    quality_cell = window.results.table.item(0, 1)
    assert "R sequence gaps: 4,824 samples" in quality_cell.toolTip()

    window.results.preview_drawer.load_session(session["session_id"])
    assert "INVALID" in window.results.preview_drawer.integrity_badge.text()
    assert "4,824 samples" in window.results.preview_drawer.integrity_detail.text()

    window.model.update_sessions([session])
    result = _sample_result()
    result["session_id"] = session["session_id"]
    model = window.model
    model._on_analysis_ready(result)
    assert "INVALID" in model.status_label.text()
    assert "4,824 samples" in model.status_label.text()

    _close(controller, window)


def test_model_timeline_moves_3d_cursor_and_selected_segment():
    controller, window = _window()
    model = window.model
    result = _sample_result()
    result["xyz"] = [(x, y, z) for (x, y), z in zip(result["xy"], (0.0, 0.2, 0.4, 0.6))]
    result["analysis"] = build_analysis(
        times=[0.0, 0.05, 0.10, 0.15],
        xy=[list(point) for point in result["xy"]],
        flags=[[] for _ in result["xy"]],
    )
    model._on_analysis_ready(result)
    assert model.trajectory_3d_view.cursor_point == result["xyz"][0]
    model.timeline.cursor.setValue(2)
    assert model.trajectory_3d_view.cursor_point == result["xyz"][2]
    model.timeline.start.setValue(0.05)
    model.timeline.stop.setValue(0.10)
    assert model.trajectory_3d_view.window_indices == (1, 2)
    _close(controller, window)


def test_model_page_surfaces_slalom_course_constraint_state():
    controller, window = _window()
    model = window.model
    result = _sample_result()
    result["course_constraint"] = {
        "applied": True,
        "heading_closure": True,
        "position_closure": True,
        "turn_count": 10,
        "removed_net_heading_deg": -28.2,
    }
    model._on_analysis_ready(result)
    _APP.processEvents()
    assert "Slalom course constraint v1: 10 turn event(s)" in model.status_label.text()
    assert "10 turn event(s)" in model.status_label.toolTip()
    assert "position closure=yes" in model.status_label.toolTip()
    _close(controller, window)


def test_model_page_session_search_and_imu_tagging():
    controller, window = _window()
    model = window.model

    # Demo sessions have 3 IMUs -> should be tagged [3-IMU]
    assert model.session_combo.count() >= 3
    assert "[3-IMU]" in model.session_combo.itemText(0)

    # Add a 2-IMU session
    two_imu_sess = {
        "session_id": "demo_two_imu_01",
        "topic": "Sprint",
        "trial_number": 99,
        "athlete": "Athlete Two",
        "quality": "GOOD",
        "sample_counts": {"L": 500, "R": 500, "C": 0},
    }
    controller.sessions.append(two_imu_sess)
    controller.sessions_changed.emit(list(controller.sessions))
    _APP.processEvents()

    # Verify [2-IMU] tag appears
    found_2imu = any(
        "[2-IMU]" in model.session_combo.itemText(i)
        and "Trial 99" in model.session_combo.itemText(i)
        for i in range(model.session_combo.count())
    )
    assert found_2imu

    # Test filtering recordings
    model.session_search.setText("Trial 99")
    _APP.processEvents()
    assert model.session_combo.count() == 1
    assert "Trial 99" in model.session_combo.itemText(0)

    # Test select_session resets filter if needed
    success = model.select_session("demo_endurance_01")
    _APP.processEvents()
    assert success
    assert str(model.session_combo.currentData()) == "demo_endurance_01"
    assert model.session_search.text() == ""  # Search query cleared to reveal target

    _close(controller, window)


def test_model_page_warns_on_3imu_model_with_2imu_recording():
    controller, window = _window()
    model = window.model

    # Add 2-IMU session
    two_imu_sess = {
        "session_id": "test_2imu_sess",
        "topic": "Sprint",
        "trial_number": 5,
        "athlete": "Athlete X",
        "quality": "GOOD",
        "sample_counts": {"L": 200, "R": 200, "C": 0},
    }
    controller.sessions = [two_imu_sess]
    controller.sessions_changed.emit(list(controller.sessions))
    _APP.processEvents()

    model.select_session("test_2imu_sess")
    _APP.processEvents()

    # Universal model: Kinematic Trajectory (XY + Yaw) -> Enabled
    for idx in range(model.model_combo.count()):
        spec = model.model_combo.itemData(idx)
        if hasattr(spec, "label") and "Kinematic" in spec.label:
            model.model_combo.setCurrentIndex(idx)
            break
    _APP.processEvents()
    assert model.generate_button.isEnabled()

    # 3-IMU model: requires Wheel C -> Disabled with warning
    for idx in range(model.model_combo.count()):
        spec = model.model_combo.itemData(idx)
        if hasattr(spec, "required_sensor_roles") and "C" in spec.required_sensor_roles:
            model.model_combo.setCurrentIndex(idx)
            break
    _APP.processEvents()
    assert not model.generate_button.isEnabled()
    assert "Requires Wheel C" in model.runtime_label.text()
    assert "2 IMUs only" in model.runtime_label.text()

    _close(controller, window)


def test_results_page_has_model_actions_and_expand_all():
    controller, window = _window()
    results = window.results
    window.stack.setCurrentWidget(results)
    _APP.processEvents()

    # Test expand all / collapse all toggle button
    assert hasattr(results, "expand_all_btn")
    assert results._topic_cards
    # Initially collapsed
    first_card = results._topic_cards[0]
    initial_expanded = bool(first_card.property("expanded"))
    results.expand_all_btn.click()
    _APP.processEvents()
    assert bool(first_card.property("expanded")) != initial_expanded
    assert not first_card.table_container.isHidden()

    # Test open in MODEL from SessionPreviewDrawer
    drawer = results.preview_drawer
    drawer.load_session("demo_sprint_01")
    _APP.processEvents()
    assert drawer.open_model_btn.isVisible()
    drawer.open_model_btn.click()
    _APP.processEvents()

    # Verify switched to MODEL tab with demo_sprint_01 selected
    assert window.stack.currentWidget() is window.model
    assert str(window.model.session_combo.currentData()) == "demo_sprint_01"

    _close(controller, window)


def test_model_page_auto_detection():
    controller, window = _window()
    model = window.model

    # Add both 3-IMU and 2-IMU sessions
    controller.sessions = [
        {
            "session_id": "sess_3imu",
            "topic": "Sprint 3IMU",
            "trial_number": 1,
            "athlete": "Athlete A",
            "quality": "GOOD",
            "sample_counts": {"L": 200, "R": 200, "C": 200},
        },
        {
            "session_id": "sess_2imu",
            "topic": "Sprint 2IMU",
            "trial_number": 2,
            "athlete": "Athlete B",
            "quality": "GOOD",
            "sample_counts": {"L": 200, "R": 200, "C": 0},
        },
    ]
    controller.sessions_changed.emit(list(controller.sessions))
    _APP.processEvents()

    # Selecting 3-IMU session -> auto-matches to the validated active v3 model.
    model.select_session("sess_3imu")
    _APP.processEvents()
    spec = model.model_combo.currentData()
    assert spec is not None
    assert "C" in spec.required_sensor_roles
    assert "v3" in spec.key.lower()

    # Selecting 2-IMU session -> auto-matches to 2-IMU dual-hub baseline
    model.select_session("sess_2imu")
    _APP.processEvents()
    spec = model.model_combo.currentData()
    assert spec is not None
    assert "C" not in spec.required_sensor_roles

    _close(controller, window)


def test_model_page_comparison_overlay():
    controller, window = _window()
    model = window.model

    assert hasattr(model, "compare_checkbox")
    assert model.compare_checkbox.accessibleName() == "modelCompareCheckbox"
    assert model.comparison_series.count() == 0

    result = _sample_result()
    result["comparison_xy"] = [(0.0, 0.0), (0.48, 0.09), (0.98, 0.38), (1.38, 0.78)]
    result["comparison_label"] = "Kinematic Trajectory (XY + Yaw)"
    model._on_analysis_ready(result)
    _APP.processEvents()

    assert model.comparison_series.count() == 4
    assert model.chart.legend().isVisible()
    assert "Dual-Hub 2-IMU" in model.comparison_series.name()

    model._invalidate_analysis()
    _APP.processEvents()
    assert model.comparison_series.count() == 0
    assert not model.chart.legend().isVisible()

    _close(controller, window)


def test_model_page_csv_export(tmp_path, monkeypatch):
    from PySide6.QtWidgets import QFileDialog

    controller, window = _window()
    model = window.model

    assert hasattr(model, "export_csv_button")
    assert model.export_csv_button.accessibleName() == "exportTrajectoryCsvButton"
    assert not model.export_csv_button.isEnabled()

    result = _sample_result()
    model._on_analysis_ready(result)
    _APP.processEvents()

    assert model.export_csv_button.isEnabled()

    target_file = str(tmp_path / "exported_trajectory.csv")
    monkeypatch.setattr(
        QFileDialog, "getSaveFileName", lambda *args, **kwargs: (target_file, "CSV files (*.csv)")
    )

    model.export_trajectory_csv()
    _APP.processEvents()

    assert os.path.isfile(target_file)
    with open(target_file, "r", encoding="utf-8") as f:
        content = f.read()
    assert "time_s,x_m,y_m,z_m,signed_speed_mps" in content
    assert "1.4" in content  # points from sample result

    model._invalidate_analysis()
    _APP.processEvents()
    assert not model.export_csv_button.isEnabled()

    _close(controller, window)


def test_model_page_image_export(tmp_path, monkeypatch):
    from PySide6.QtWidgets import QFileDialog

    controller, window = _window()
    model = window.model

    assert hasattr(model, "export_image_button")
    assert model.export_image_button.accessibleName() == "exportTrajectoryImageButton"
    assert not model.export_image_button.isEnabled()

    result = _sample_result()
    model._on_analysis_ready(result)
    _APP.processEvents()

    assert model.export_image_button.isEnabled()

    target_file = str(tmp_path / "trajectory_snapshot.png")
    monkeypatch.setattr(
        QFileDialog,
        "getSaveFileName",
        lambda *args, **kwargs: (target_file, "PNG Image (*.png)"),
    )

    model.export_trajectory_image()
    _APP.processEvents()

    assert os.path.isfile(target_file)
    assert os.path.getsize(target_file) > 0

    model._invalidate_analysis()
    _APP.processEvents()
    assert not model.export_image_button.isEnabled()

    _close(controller, window)


def test_3d_export_preserves_height_and_selected_view(tmp_path, monkeypatch):
    from PySide6.QtWidgets import QFileDialog

    controller, window = _window()
    model = window.model
    window.stack.setCurrentWidget(model)
    result = _sample_result()
    result["xyz"] = [(x, y, z) for (x, y), z in zip(result["xy"], (0.0, 0.1, 0.2, 0.3))]
    model._on_analysis_ready(result)
    _APP.processEvents()
    assert model.plot_tabs.currentWidget() is model.trajectory_3d_view

    targets = iter((str(tmp_path / "path.csv"), str(tmp_path / "view.png")))
    monkeypatch.setattr(QFileDialog, "getSaveFileName", lambda *args, **kwargs: (next(targets), ""))
    model.export_trajectory_csv()
    model.export_trajectory_image()
    assert "z_m" in (tmp_path / "path.csv").read_text(encoding="utf-8")
    assert "0.300000" in (tmp_path / "path.csv").read_text(encoding="utf-8")
    assert (tmp_path / "view.png").stat().st_size > 0
    _close(controller, window)


def test_model_page_multi_model_and_c3d_comparison():
    controller, window = _window()
    model = window.model

    assert hasattr(model, "comp_v8")
    assert model.comp_v8.text() == "SOF-3IMU v2"
    assert model.comp_v3.text() == "PHC-3IMU v1"
    assert model.comp_v2.text() == "PBF-3IMU v1"
    assert model.comp_v7.isHidden()
    assert model.comp_v6.isHidden()
    assert model.comp_v5.isHidden()
    assert model.comp_v4.isHidden()
    assert hasattr(model, "comp_v3")
    assert hasattr(model, "comp_v2")
    assert hasattr(model, "comp_c3d")
    assert hasattr(model, "import_c3d_button")

    result = _sample_result()
    result["comp_dual_hub_xy"] = [(0.0, 0.0), (0.5, 0.0), (1.0, 0.0)]
    result["comp_v8_xy"] = [(0.0, 0.0), (0.53, -0.01), (1.03, 0.00)]
    result["comp_v7_xy"] = [(0.0, 0.0), (0.52, -0.01), (1.02, 0.01)]
    result["comp_v6_xy"] = [(0.0, 0.0), (0.51, 0.00), (1.01, 0.02)]
    result["comp_v5_xy"] = [(0.0, 0.0), (0.50, 0.01), (1.00, 0.03)]
    result["comp_v4_xy"] = [(0.0, 0.0), (0.49, 0.02), (0.99, 0.05)]
    result["comp_v3_xy"] = [(0.0, 0.0), (0.47, 0.04), (0.95, 0.08)]
    result["comp_v2_xy"] = [(0.0, 0.0), (0.46, 0.05), (0.92, 0.10)]
    result["ground_truth_xy"] = [(0.0, 0.0), (0.495, 0.01), (0.995, 0.02)]

    model._on_analysis_ready(result)
    _APP.processEvents()

    assert model.comparison_series.count() == 3
    assert model.comp_v8_series.count() == 3
    assert model.comp_v7_series.count() == 3
    assert model.comp_v6_series.count() == 3
    assert model.comp_v5_series.count() == 3
    assert model.comp_v4_series.count() == 3
    assert model.comp_v3_series.count() == 3
    assert model.comp_v2_series.count() == 3
    assert model.ground_truth_series.count() == 3
    assert model.chart.legend().isVisible()

    # Toggle one off
    model.comp_v2.setChecked(False)
    _APP.processEvents()
    assert model.comp_v2_series.count() == 0
    assert model.comp_v4_series.count() == 3

    model._invalidate_analysis()
    _APP.processEvents()
    assert model.comp_v8_series.count() == 0
    assert model.comp_v7_series.count() == 0
    assert model.comp_v6_series.count() == 0
    assert model.comp_v5_series.count() == 0
    assert model.comp_v4_series.count() == 0
    assert model.ground_truth_series.count() == 0

    _close(controller, window)


def test_model_page_responsive_layout_and_scrolling():
    controller, window = _window()
    model = window.model
    window.stack.setCurrentWidget(model)
    _APP.processEvents()

    # Window minimum size allows compact displays (768p and high DPI scaling)
    assert window.minimumWidth() <= 980
    assert window.minimumHeight() <= 560

    # Model page has a dedicated scroll area for small screens
    assert hasattr(model, "scroll_area")
    assert model.scroll_area.widgetResizable()

    # Compare checkboxes and export buttons live on separate rows and are visible
    assert model.comp_dual_hub.isVisible()
    assert model.comp_v8.isVisible()
    assert model.import_c3d_button.isVisible()
    assert model.export_image_button.isVisible()
    assert model.export_csv_button.isVisible()

    # Resize window to compact screen resolution (980x560)
    window.resize(980, 560)
    _APP.processEvents()

    # Verify trajectory generation and layout stability at compact size
    result = _sample_result()
    model._on_analysis_ready(result)
    _APP.processEvents()

    assert model.chart_view.isVisible()
    plot = model.chart.plotArea()
    assert plot.width() > 0
    assert plot.height() > 0
    assert plot.width() == pytest.approx(plot.height(), abs=1.0)

    _close(controller, window)
