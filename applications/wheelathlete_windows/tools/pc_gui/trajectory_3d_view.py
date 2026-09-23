"""Mouse-orbit trajectory view with honest handling of planar-only outputs."""

from __future__ import annotations

import math

from PySide6.QtCore import QPointF, Qt
from PySide6.QtGui import QColor, QPainter, QPen, QPolygonF
from PySide6.QtWidgets import QWidget


class Trajectory3DView(QWidget):
    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.setObjectName("trajectory3DView")
        self.setAccessibleName("Interactive 3D trajectory")
        self.setMinimumHeight(280)
        self.setMouseTracking(True)
        self.points: list[tuple[float, float, float]] = []
        self._source_points: list[tuple[float, float, float]] = []
        self._display_indices: list[int] = []
        self.cursor_index: int | None = None
        self.window_indices: tuple[int, int] | None = None
        self.has_vertical = False
        self.azimuth = -40.0
        self.elevation = 28.0
        self.zoom = 1.0
        self._drag_position = None
        self._update_description()

    def _update_description(self) -> None:
        dimension = "Measured model Z" if self.has_vertical else "Z unavailable; planar path shown at Z=0"
        self.setAccessibleDescription(f"{dimension}. Drag to orbit, wheel to zoom, double-click to reset.")

    def set_trajectory(self, points, *, has_vertical: bool) -> None:
        values = []
        for point in points:
            if len(point) != (3 if has_vertical else 2) or not all(math.isfinite(float(v)) for v in point):
                raise ValueError("Trajectory points must be finite XY or XYZ coordinates")
            values.append(tuple(float(v) for v in point) if has_vertical else (float(point[0]), float(point[1]), 0.0))
        stride = max(1, len(values) // 5000)
        self._source_points = values
        self._display_indices = list(range(0, len(values), stride))
        if values and self._display_indices[-1] != len(values) - 1:
            self._display_indices.append(len(values) - 1)
        self.points = [values[index] for index in self._display_indices]
        self.cursor_index = None
        self.window_indices = None
        self.has_vertical = has_vertical
        self._update_description()
        self.update()

    @property
    def cursor_point(self) -> tuple[float, float, float] | None:
        return None if self.cursor_index is None else self._source_points[self.cursor_index]

    def set_cursor(self, index: int) -> None:
        if not 0 <= index < len(self._source_points):
            raise IndexError("Trajectory cursor is outside the recording")
        self.cursor_index = index
        self.update()

    def set_window(self, first: int, last: int) -> None:
        if not 0 <= first <= last < len(self._source_points):
            raise IndexError("Trajectory window is outside the recording")
        self.window_indices = (first, last)
        self.update()

    def reset_view(self) -> None:
        self.azimuth, self.elevation, self.zoom = -40.0, 28.0, 1.0
        self.update()

    def orbit(self, horizontal_degrees: float, vertical_degrees: float) -> None:
        self.azimuth = (self.azimuth + horizontal_degrees) % 360.0
        self.elevation = max(-89.0, min(89.0, self.elevation + vertical_degrees))
        self.update()

    @property
    def view_center(self) -> tuple[float, float, float] | None:
        if not self.points:
            return None
        if self.cursor_index is not None:
            return self._source_points[self.cursor_index]
        return tuple(
            (min(p[i] for p in self.points) + max(p[i] for p in self.points)) / 2
            for i in range(3)
        )

    def project_points(self) -> list[tuple[float, float]]:
        center = self.view_center
        if center is None:
            return []
        return [self._project(point, center) for point in self.points]

    def _project(self, point, center) -> tuple[float, float]:
        x, y, z = (point[i] - center[i] for i in range(3))
        az, el = math.radians(self.azimuth), math.radians(self.elevation)
        horizontal = math.cos(az) * x - math.sin(az) * y
        depth = math.sin(az) * x + math.cos(az) * y
        return horizontal, math.cos(el) * z - math.sin(el) * depth

    def mousePressEvent(self, event) -> None:
        if event.button() == Qt.MouseButton.LeftButton:
            self._drag_position = event.position()
            self.setCursor(Qt.CursorShape.ClosedHandCursor)
        super().mousePressEvent(event)

    def mouseMoveEvent(self, event) -> None:
        if self._drag_position is not None:
            delta = event.position() - self._drag_position
            self.orbit(delta.x() * 0.45, -delta.y() * 0.45)
            self._drag_position = event.position()
        super().mouseMoveEvent(event)

    def mouseReleaseEvent(self, event) -> None:
        self._drag_position = None
        self.unsetCursor()
        super().mouseReleaseEvent(event)

    def mouseDoubleClickEvent(self, event) -> None:
        self.reset_view()
        super().mouseDoubleClickEvent(event)

    def wheelEvent(self, event) -> None:
        self.zoom = max(0.35, min(5.0, self.zoom * (1.12 ** (event.angleDelta().y() / 120))))
        self.update()
        event.accept()

    def paintEvent(self, event) -> None:
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)
        painter.fillRect(self.rect(), QColor("#f8fafc"))
        painter.setPen(QColor("#334155"))
        painter.drawText(18, 27, "3D trajectory" if self.has_vertical else "Planar trajectory in 3D view")
        painter.setPen(QColor("#64748b"))
        painter.drawText(18, 47, "Drag to rotate  ·  Wheel to zoom  ·  Double-click to reset")
        if not self.points:
            painter.drawText(self.rect().adjusted(18, 65, -18, -18), Qt.AlignmentFlag.AlignCenter,
                             "Generate a trajectory to view it here")
            return
        if not self.has_vertical:
            painter.setPen(QColor("#b45309"))
            painter.drawText(18, 68, "Z unavailable — height is shown as zero for viewing only")

        center = self.view_center
        assert center is not None
        projected = [self._project(p, center) for p in self.points]
        extent = max(max(p[i] for p in self.points) - min(p[i] for p in self.points) for i in range(3))
        grid_half = max(extent * 0.4, 0.5)
        ground = min(p[2] for p in self.points)
        anchor = (center[0], center[1], ground)
        grid = []
        for n in range(-2, 3):
            coordinate = grid_half * n / 2
            grid.extend([
                ((center[0] - grid_half, center[1] + coordinate, ground),
                 (center[0] + grid_half, center[1] + coordinate, ground)),
                ((center[0] + coordinate, center[1] - grid_half, ground),
                 (center[0] + coordinate, center[1] + grid_half, ground)),
            ])
        all_projected = projected + [self._project(p, center) for line in grid for p in line]
        span = max(max(abs(p[i]) for p in all_projected) for i in range(2))
        scale = min((self.width() - 60) / 2, (self.height() - 125) / 2) / max(span, 0.1) * self.zoom
        origin = QPointF(self.width() / 2, (self.height() + 55) / 2)

        def screen(point) -> QPointF:
            u, v = self._project(point, center)
            return QPointF(origin.x() + u * scale, origin.y() - v * scale)

        painter.setPen(QPen(QColor("#dbe4ee"), 1))
        for first, last in grid:
            painter.drawLine(screen(first), screen(last))
        axes = (("X", (center[0] + grid_half, center[1], ground), "#dc2626"),
                ("Y", (center[0], center[1] + grid_half, ground), "#16a34a"),
                ("Z", (center[0], center[1], ground + grid_half), "#2563eb"))
        for label, endpoint, color in axes:
            painter.setPen(QPen(QColor(color), 2))
            painter.drawLine(screen(anchor), screen(endpoint))
            painter.drawText(screen(endpoint) + QPointF(5, -4), label)
        painter.setPen(QPen(QColor("#cbd5e1"), 2.5))
        painter.drawPolyline(QPolygonF([screen(p) for p in self.points]))
        if self.window_indices is not None:
            first, last = self.window_indices
            selected = [self._source_points[first]]
            selected.extend(self.points[i] for i, index in enumerate(self._display_indices) if first < index < last)
            selected.append(self._source_points[last])
            painter.setPen(QPen(QColor("#2563eb"), 4))
            painter.drawPolyline(QPolygonF([screen(p) for p in selected]))
        if self.cursor_index is not None:
            visited = [self.points[i] for i, index in enumerate(self._display_indices) if index < self.cursor_index]
            visited.append(self._source_points[self.cursor_index])
            painter.setPen(QPen(QColor("#0f766e"), 3))
            painter.drawPolyline(QPolygonF([screen(p) for p in visited]))
        for point, color in ((self.points[0], "#0f766e"), (self.points[-1], "#ea580c")):
            painter.setPen(QPen(QColor("#ffffff"), 2))
            painter.setBrush(QColor(color))
            painter.drawEllipse(screen(point), 5, 5)
        if self.cursor_index is not None:
            painter.setPen(QPen(QColor("#ffffff"), 2))
            painter.setBrush(QColor("#e11d48"))
            painter.drawEllipse(screen(self._source_points[self.cursor_index]), 8, 8)
            if self.has_vertical:
                painter.setPen(QColor("#334155"))
                painter.drawText(18, 68, f"Current Z {self._source_points[self.cursor_index][2]:+.2f} m")
        painter.setPen(QColor("#475569"))
        painter.drawText(18, self.height() - 15, "● Start    ● End    ● Timeline cursor    Axes and grid in metres")
