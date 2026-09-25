import os

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PySide6.QtWidgets import QApplication

from tools.pc_gui.trajectory_3d_view import Trajectory3DView, fit_scale_for_view


_APP = QApplication.instance() or QApplication([])


def test_3d_view_preserves_real_z_and_orbit_does_not_change_data():
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


def test_planar_trajectory_reports_z_unavailable():
    view = Trajectory3DView()
    view.set_trajectory([(0.0, 0.0), (1.0, 2.0)], has_vertical=False)
    assert view.points == [(0.0, 0.0, 0.0), (1.0, 2.0, 0.0)]
    assert "Z unavailable" in view.accessibleDescription()


def test_flexible_scale_fits_both_dimensions_without_axis_stretching():
    wide = fit_scale_for_view(x_span=4.0, y_span=1.0, width=600, height=400)
    taller = fit_scale_for_view(x_span=1.0, y_span=4.0, width=600, height=400)
    assert wide == 121.5
    assert taller == 61.875
    assert fit_scale_for_view(x_span=8.0, y_span=2.0, width=600, height=400) < wide


def test_auto_fit_uses_full_resolution_bounds_even_when_display_is_decimated():
    view = Trajectory3DView()
    points = [(float(i), 0.0, 0.0) for i in range(10002)]
    points[5001] = (100_000.0, 0.0, 0.0)
    view.set_trajectory(points, has_vertical=True)
    assert len(view.points) < len(points)
    fitted_scale = view.fitted_scale(600, 400)
    reference = Trajectory3DView()
    reference.set_trajectory([points[0], points[5001], points[-1]], has_vertical=True)
    assert fitted_scale == reference.fitted_scale(600, 400)
    assert view.cursor_point is None
    view.set_cursor(5001)
    assert view.cursor_point == points[5001]
    view.set_trajectory([], has_vertical=False)
    assert view.cursor_point is None
