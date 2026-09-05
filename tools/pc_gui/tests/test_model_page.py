import os
from pathlib import Path

import pytest
from PySide6.QtCore import Qt
from PySide6.QtWidgets import QApplication

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from tools.pc_gui.controller import DemoController
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


def _sample_result() -> dict:
    return {
        "session_id": "demo_sprint_01",
        "topic": "Sprint",
        "trial_number": 1,
        "model_label": "TCN + BiLSTM M4 — validated",
        "xy": [(0.0, 0.0), (0.5, 0.1), (1.0, 0.4), (1.4, 0.8)],
        "point_count": 4,
        "path_length_m": 1.72,
        "endpoint_m": 1.61,
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
    assert window.model.browse_model_button.accessibleName() == "browseModelCheckpointButton"

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
    assert "Sprint" in model.chart.title()
    assert "native 100 Hz" in model.status_label.text()

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

    _close(controller, window)


def test_model_page_browse_can_select_checkpoint_from_file_explorer(monkeypatch, tmp_path: Path):
    controller, window = _window()
    model = window.model
    checkpoint = tmp_path / "my_experiment.pt"
    checkpoint.write_bytes(b"not-loaded-during-browse")

    monkeypatch.setattr(
        "tools.pc_gui.main_window.QFileDialog.getOpenFileName",
        lambda *args, **kwargs: (str(checkpoint), "PyTorch checkpoints (*.pt *.pth)"),
    )

    model.browse_model()
    _APP.processEvents()

    selected = model.model_combo.currentData()
    assert selected is not None
    assert selected.checkpoint == checkpoint.resolve()
    assert "my_experiment" in model.model_combo.currentText()
    assert str(checkpoint.resolve()) in model.model_detail.text()

    _close(controller, window)
