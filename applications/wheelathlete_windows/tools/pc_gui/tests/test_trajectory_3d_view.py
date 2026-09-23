import os

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PySide6.QtCore import QPoint, Qt
from PySide6.QtTest import QTest
from PySide6.QtWidgets import QApplication

from tools.pc_gui.trajectory_3d_view import Trajectory3DView


_APP = QApplication.instance() or QApplication([])


def test_3d_view_preserves_real_z_and_rotates_without_changing_data():
    view = Trajectory3DView()
    points = [(0.0, 0.0, 0.0), (1.0, 0.0, 0.5), (1.0, 1.0, 1.0)]
    view.set_trajectory(points, has_vertical=True)
    first = view.project_points()
    view.orbit(45, 20)
    assert view.project_points() != first
    assert view.points == points
    assert view.has_vertical
    view.reset_view()
    assert view.project_points() == first


def test_3d_view_labels_planar_data_without_inventing_height():
    view = Trajectory3DView()
    view.set_trajectory([(0.0, 0.0), (1.0, 2.0)], has_vertical=False)
    assert view.points == [(0.0, 0.0, 0.0), (1.0, 2.0, 0.0)]
    assert "Z unavailable" in view.accessibleDescription()


def test_3d_cursor_tracks_full_resolution_points_after_display_sampling():
    view = Trajectory3DView()
    points = [(float(i), 0.0, i / 100.0) for i in range(10002)]
    view.set_trajectory(points, has_vertical=True)
    static_center = view.view_center
    view.set_cursor(5001)
    view.set_window(4001, 6001)
    assert view.cursor_point == points[5001]
    assert view.view_center == points[5001]
    assert view.view_center != static_center
    assert view.cursor_index == 5001
    assert view.window_indices == (4001, 6001)
    view.set_trajectory([], has_vertical=False)
    assert view.cursor_point is None
    assert view.window_indices is None


def test_mouse_drag_orbits_view():
    view = Trajectory3DView()
    view.resize(600, 400)
    view.show()
    _APP.processEvents()
    initial = view.azimuth
    QTest.mousePress(view, Qt.MouseButton.LeftButton, pos=QPoint(100, 100))
    QTest.mouseMove(view, QPoint(170, 100))
    QTest.mouseRelease(view, Qt.MouseButton.LeftButton, pos=QPoint(170, 100))
    assert view.azimuth != initial
    view.close()
