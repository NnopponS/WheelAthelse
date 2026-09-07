import csv
import json
import os
from pathlib import Path

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault(
    "WHEELATHLETE_MODEL_DIR", str(Path(__file__).parent / "_empty_model_library")
)

import pytest
from PySide6.QtCore import Qt
from PySide6.QtTest import QTest
from PySide6.QtWidgets import QApplication

from tools.pc_gui.analysis_contract import build_analysis
from tools.pc_gui.analysis_timeline import AnalysisTimeline
from tools.pc_gui.controller import DemoController
from tools.pc_gui.main_window import ModelPage

APP = QApplication.instance() or QApplication([])


def result(n=120):
    times = [4.02 + i * 0.05 for i in range(n)]
    xy = [[i * 0.03, i * 0.001] for i in range(n)]
    if n > 5000:
        xy[3333][1] = 40.0  # Full bounds/cursor must retain a decimated peak.
    a = build_analysis(
        times=times,
        xy=xy,
        flags=[[] for _ in times],
        signed_speed=[0.6] * n,
        yaw=[i * 0.01 for i in range(n)],
        yaw_rate=[0.2] * n,
        metadata={"session_id": "synthetic_ui"},
    )
    return {
        "session_id": "synthetic_ui",
        "topic": "Source UI fixture",
        "trial_number": 1,
        "model_label": "Frozen-model contract fixture",
        "xy": xy,
        "analysis": a,
        "point_count": n,
        "path_length_m": (n - 1) * 0.03,
        "endpoint_m": (n - 1) * 0.03,
        "net_yaw_deg": 0.0,
        "yaw_source": "fixture",
        "yaw_delay_frames": 0,
        "preprocess": {
            "aligned_samples": n * 5,
            "model_steps": n,
            "warnings": ["Synthetic UI verification only."],
        },
    }


@pytest.fixture
def page():
    controller = DemoController()
    p = ModelPage(controller)
    p.resize(1320, 768)
    p.show()
    APP.processEvents()
    yield p
    p.close()
    p.deleteLater()
    controller.close()
    APP.processEvents()


def test_exact_cursor_and_window_survive_decimation(page, tmp_path):
    r = result(10001)
    page._on_analysis_ready(r)
    APP.processEvents()
    panel = page.timeline
    panel.cursor.setValue(3333)
    APP.processEvents()
    point = page.cursor_series.at(0)
    assert point.x() == r["xy"][3333][0]
    assert point.y() == 40.0
    assert page._trajectory_bounds[-1] >= 40.0
    assert "170.670" in panel.time_label.text()
    a, b = 3320, 3340
    panel.start.setValue(r["analysis"]["samples"][a]["time_s"])
    panel.stop.setValue(r["analysis"]["samples"][b]["time_s"])
    assert panel.last_statistics["samples"] == 21
    out = panel.export_to(tmp_path)
    rows = list(csv.DictReader((out / "timeline.csv").open(encoding="utf-8")))
    meta = json.loads((out / "metadata.json").read_text())
    assert len(rows) == 10001
    assert float(rows[3333]["y_m"]) == 40.0
    assert meta["selected_window"]["start_index"] == a
    assert meta["selected_window"]["stop_index_exclusive"] == b + 1
    assert r["analysis"]["samples"][a]["x_m"] == a * 0.03


def test_keyboard_cursor_moves_one_original_sample(page):
    page._on_analysis_ready(result())
    page.timeline.cursor.setFocus()
    QTest.keyClick(page.timeline.cursor, Qt.Key.Key_Right)
    APP.processEvents()
    assert page.timeline.cursor.value() == 1
    assert page.cursor_series.at(0).x() == 0.03


def test_stale_worker_result_is_not_shown_after_selection_change(page):
    r = result()
    r["_request_generation"] = page._generation
    page._invalidate_analysis()
    page._on_analysis_ready(r)
    assert page.trajectory_series.count() == 0
    assert page.timeline.analysis is None
    assert "stale" in page.status_label.text()


def test_missing_derivative_is_visible_not_zero_and_empty_channel_safe(page):
    r = result()
    page._on_analysis_ready(r)
    assert "Unavailable" in page.timeline.selected_label.text()
    page.timeline.cursor.setValue(10)
    assert "0.00 m/s2" in page.timeline.selected_label.text()
    a = build_analysis(
        times=[p["time_s"] for p in r["analysis"]["samples"]],
        xy=r["xy"],
        flags=[[] for _ in r["xy"]],
    )
    page.timeline.set_analysis(a)
    page.timeline.channel.setCurrentIndex(3)
    assert "unavailable" in page.timeline.chart.title()
    assert "Yaw Unavailable" in page.timeline.selected_label.text()


def test_backward_window_is_clamped_without_negative_interval(page):
    page._on_analysis_ready(result())
    page.timeline.start.setValue(7.0)
    page.timeline.stop.setValue(5.0)
    assert page.timeline.start.value() <= page.timeline.stop.value()
    assert page.timeline.last_statistics["samples"] >= 1


def test_reset_disables_stale_export_and_clears_plot(page):
    page._on_analysis_ready(result())
    assert page.timeline.export_button.isEnabled()
    page._invalidate_analysis()
    assert not page.timeline.export_button.isEnabled()
    assert page.cursor_series.count() == 0
    assert page.timeline.last_statistics is None


def test_export_invalid_selection_leaves_no_files(tmp_path):
    panel = AnalysisTimeline()
    with pytest.raises(ValueError, match="No analysis"):
        panel.export_to(tmp_path)
    assert list(tmp_path.iterdir()) == []
    panel.deleteLater()
