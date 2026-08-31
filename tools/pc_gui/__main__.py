from __future__ import annotations

import argparse
import logging
import sys
from pathlib import Path

from PySide6.QtWidgets import QApplication

from .controller import AcquisitionController, DemoController
from .main_window import MainWindow


def _configure_logging() -> Path:
    root = Path.home() / "Documents" / "WheelAthlete" / "Logs"
    root.mkdir(parents=True, exist_ok=True)
    path = root / "python-pc-app.log"
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
        handlers=[logging.FileHandler(path, encoding="utf-8"), logging.StreamHandler()],
    )
    return path


def _install_exception_hook(log_path: Path) -> None:
    logger = logging.getLogger("wheelathlete.gui")

    def hook(exc_type, exc_value, traceback) -> None:  # type: ignore[no-untyped-def]
        logger.critical("Unhandled GUI exception", exc_info=(exc_type, exc_value, traceback))
        sys.__excepthook__(exc_type, exc_value, traceback)
        print(f"Crash details were written to {log_path}", file=sys.stderr)

    sys.excepthook = hook


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="WheelAthlete Python Research Edition")
    parser.add_argument("--demo", action="store_true", help="show synthetic preview data; never writes research evidence")
    parser.add_argument("--port", type=int, default=8765, help="localhost acquisition-daemon port")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    log_path = _configure_logging()
    _install_exception_hook(log_path)
    repo_root = Path(__file__).resolve().parents[2]

    app = QApplication(sys.argv)
    app.setApplicationName("WheelAthlete Python Research Edition")
    app.setOrganizationName("WheelAthlete")
    controller = DemoController() if args.demo else AcquisitionController(repo_root=repo_root, port=args.port)
    window = MainWindow(controller, demo=args.demo)
    window.show()
    window.start()
    return int(app.exec())


if __name__ == "__main__":
    raise SystemExit(main())
