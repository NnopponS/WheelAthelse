import os
import time
from pathlib import Path

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PySide6.QtWidgets import QApplication

from tools.pc_gui.controller import DemoController


_APP = QApplication.instance() or QApplication([])


def _wait_for(app: QApplication, predicate, timeout_s: float = 5.0) -> None:
    deadline = time.monotonic() + timeout_s
    while not predicate() and time.monotonic() < deadline:
        app.processEvents()
        time.sleep(0.01)


def test_single_csv_export_runs_in_worker_and_reports_progress_and_failure(tmp_path: Path):
    controller = DemoController()
    progress: list[tuple[int, int, str]] = []
    completed: list[list[str]] = []
    failed: list[str] = []
    controller.export_progress.connect(lambda *args: progress.append(args))
    controller.export_completed.connect(completed.append)
    controller.export_failed.connect(failed.append)
    output = tmp_path / "one.csv"

    controller.export_session("demo-session", str(output))
    _wait_for(_APP, lambda: bool(completed or failed))

    assert not failed
    assert completed == [[str(output)]]
    assert [item[:2] for item in progress] == [(0, 1), (1, 1)]
    assert output.is_file()
    original = output.read_bytes()

    controller.export_session("demo-session", str(output))
    _wait_for(_APP, lambda: bool(failed))
    assert failed and "exist" in failed[0].lower()
    assert output.read_bytes() == original

    blocked_directory = tmp_path / "not-a-directory"
    blocked_directory.write_text("file", encoding="utf-8")
    batch_errors: list[str] = []
    controller.export_failed.connect(batch_errors.append)
    assert controller.export_sessions(
        [{"session_id": "demo-session"}], blocked_directory
    ) == []
    assert batch_errors and "export folder" in batch_errors[0].lower()
