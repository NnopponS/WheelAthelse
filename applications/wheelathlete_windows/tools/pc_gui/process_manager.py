from __future__ import annotations

import socket
import sys
from pathlib import Path

from PySide6.QtCore import QObject, QProcess, QProcessEnvironment, Signal


class DaemonProcessManager(QObject):
    log_line = Signal(str)
    started = Signal()
    exited = Signal(int)

    def __init__(
        self,
        *,
        repo_root: Path,
        port: int = 8765,
        journal_root: Path | None = None,
        parent: QObject | None = None,
    ) -> None:
        super().__init__(parent)
        self.repo_root = repo_root
        self.port = port
        self.journal_root = journal_root
        self.process = QProcess(self)
        self.process.setProcessChannelMode(QProcess.ProcessChannelMode.MergedChannels)
        self.process.readyReadStandardOutput.connect(self._read_output)
        self.process.started.connect(self.started)
        self.process.finished.connect(lambda code, _status: self.exited.emit(int(code)))
        self._owns_process = False

    @property
    def owns_process(self) -> bool:
        return self._owns_process

    def daemon_reachable(self, timeout_s: float = 0.15) -> bool:
        try:
            with socket.create_connection(("127.0.0.1", self.port), timeout=timeout_s):
                return True
        except OSError:
            return False

    def ensure_running(self) -> bool:
        """Start a source daemon only when no daemon is already listening.

        Returns ``True`` when this manager started the daemon and ``False``
        when an existing daemon was detected.
        """
        if self.daemon_reachable():
            self._owns_process = False
            return False
        if self.process.state() != QProcess.ProcessState.NotRunning:
            return self._owns_process
        if getattr(sys, "frozen", False):
            app_dir = Path(sys.executable).parent
            daemon_candidates = (
                app_dir / "_internal" / "WheelAthleteDaemon.exe",
                app_dir / "WheelAthleteDaemon.exe",
                app_dir.parent / "WheelAthleteDaemon" / "WheelAthleteDaemon.exe",
            )
            daemon_exe = next(
                (path for path in daemon_candidates if path.exists()),
                daemon_candidates[0],
            )
            if not daemon_exe.exists():
                self.log_line.emit(f"Bundled daemon not found: {daemon_exe}")
                return False
            program = str(daemon_exe)
            args = ["--port", str(self.port)]
        else:
            program = sys.executable
            args = ["-m", "tools.pc_acquisition.daemon", "--port", str(self.port)]
        if self.journal_root is not None:
            args += ["--journal-root", str(self.journal_root)]
        self.process.setWorkingDirectory(str(self.repo_root))
        environment = QProcessEnvironment.systemEnvironment()
        environment.insert("PYTHONUNBUFFERED", "1")
        self.process.setProcessEnvironment(environment)
        self.process.start(program, args)
        self._owns_process = True
        return True

    def stop_if_owned(self, *, recording_active: bool) -> None:
        """Stop the child daemon only when it is safe to do so.

        If a recording is active the daemon is deliberately left running so a
        GUI close/crash cannot destroy the authoritative acquisition session.
        """
        if not self._owns_process or recording_active:
            return
        if self.process.state() == QProcess.ProcessState.NotRunning:
            return
        self.process.terminate()
        if not self.process.waitForFinished(2000):
            self.process.kill()
            self.process.waitForFinished(1000)

    def _read_output(self) -> None:
        text = bytes(self.process.readAllStandardOutput()).decode("utf-8", errors="replace")
        for line in text.splitlines():
            if line.strip():
                self.log_line.emit(line.rstrip())
