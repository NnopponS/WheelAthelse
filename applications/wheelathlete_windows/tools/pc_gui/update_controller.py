from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from threading import Thread

from PySide6.QtCore import QObject, QTimer, Signal

from .update_service import (
    UpdateError,
    UpdateManifest,
    current_version,
    download_update,
    fetch_manifest,
    launch_installer,
    self_update_supported,
    update_available,
)


@dataclass(frozen=True)
class UpdateViewState:
    status: str = "idle"
    current_version: str = "0.0.0"
    available_version: str = ""
    message: str = ""
    progress_percent: int = 0
    install_supported: bool = False


class UpdateController(QObject):
    changed = Signal(object)
    _manifest_ready = Signal(object)
    _download_ready = Signal(object)
    _worker_error = Signal(str)
    _download_progress = Signal(int)

    def __init__(self, *, app_root: Path, parent: QObject | None = None) -> None:
        super().__init__(parent)
        self.app_root = app_root
        self.manifest: UpdateManifest | None = None
        self.downloaded_installer: Path | None = None
        self._busy = False
        self.state = UpdateViewState(
            current_version=current_version(app_root),
            install_supported=self_update_supported(),
        )
        self._timer = QTimer(self)
        self._timer.setInterval(6 * 60 * 60 * 1000)
        self._timer.timeout.connect(self.check)
        self._manifest_ready.connect(self._on_manifest)
        self._download_ready.connect(self._on_downloaded)
        self._worker_error.connect(self._on_error)
        self._download_progress.connect(self._on_progress)

    def start(self) -> None:
        # Source/demo executions keep the manual Check updates control but do
        # not create background network traffic. Installed PyInstaller builds
        # check shortly after startup and then every six hours.
        if not self.state.install_supported:
            return
        self._timer.start()
        QTimer.singleShot(1800, self.check)

    def stop(self) -> None:
        self._timer.stop()

    def _set_state(self, **changes: object) -> None:
        values = self.state.__dict__.copy()
        values.update(changes)
        self.state = UpdateViewState(**values)
        self.changed.emit(self.state)

    def check(self) -> None:
        if self._busy:
            return
        self._busy = True
        self._set_state(status="checking", message="Checking for updates…")

        def worker() -> None:
            try:
                self._manifest_ready.emit(fetch_manifest())
            except Exception as exc:
                self._worker_error.emit(str(exc))

        Thread(target=worker, name="wheelathlete-update-check", daemon=True).start()

    def _on_manifest(self, manifest: UpdateManifest) -> None:
        self._busy = False
        self.manifest = manifest
        self.downloaded_installer = None
        if update_available(self.state.current_version, manifest.version):
            self._set_state(
                status="available",
                available_version=manifest.version,
                message=f"WheelAthlete {manifest.version} is available",
                progress_percent=0,
            )
        else:
            self._set_state(
                status="current",
                available_version="",
                message=f"WheelAthlete {self.state.current_version} is up to date",
                progress_percent=0,
            )

    def download(self) -> None:
        if self._busy:
            return
        if self.manifest is None:
            self.check()
            return
        if not update_available(self.state.current_version, self.manifest.version):
            self._set_state(status="current", message="WheelAthlete is already up to date")
            return
        self._busy = True
        self._set_state(status="downloading", message="Downloading verified installer…")

        def progress(done: int, total: int) -> None:
            percent = 0 if total <= 0 else max(0, min(100, int(done * 100 / total)))
            self._download_progress.emit(percent)

        def worker() -> None:
            try:
                path = download_update(self.manifest.windows, progress=progress)
                self._download_ready.emit(path)
            except Exception as exc:
                self._worker_error.emit(str(exc))

        Thread(target=worker, name="wheelathlete-update-download", daemon=True).start()

    def _on_progress(self, percent: int) -> None:
        self._set_state(
            status="downloading",
            progress_percent=percent,
            message=f"Downloading verified installer… {percent}%",
        )

    def _on_downloaded(self, path: Path) -> None:
        self._busy = False
        self.downloaded_installer = path
        if self.state.install_supported:
            message = "Update verified and ready to install"
        else:
            message = "Update verified; self-install is available in the packaged Windows app"
        self._set_state(status="ready", progress_percent=100, message=message)

    def _on_error(self, message: str) -> None:
        self._busy = False
        self._set_state(status="error", message=message, progress_percent=0)

    def install(self) -> None:
        if self.downloaded_installer is None:
            raise UpdateError("No verified installer is ready")
        launch_installer(self.downloaded_installer)
