from pathlib import Path
import base64

import pytest

from tools.pc_gui.cleanup import (
    cleanup_wheelathlete_data,
    installed_application_data_root,
    portable_application_root,
)
from tools.pc_gui import cleanup


def test_cleanup_removes_only_wheelathlete_managed_data(tmp_path: Path):
    root = tmp_path / "WheelAthlete"
    outside = tmp_path / "custom-recordings"
    outside.mkdir()
    (outside / "keep.waj").write_text("recording", encoding="utf-8")
    for name in ("PC Sessions", "Imported CSV", "Exports", "Model", "Logs"):
        folder = root / name
        folder.mkdir(parents=True)
        (folder / "data.bin").write_bytes(b"private")
    (root / "gui_settings.json").write_text("{}", encoding="utf-8")
    (root / "experiments.json").write_text("[]", encoding="utf-8")
    (root / "notes.txt").write_text("user file", encoding="utf-8")

    removed = cleanup_wheelathlete_data(root)

    assert len(removed) == 7
    assert not (root / "PC Sessions").exists()
    assert not (root / "Imported CSV").exists()
    assert not (root / "Exports").exists()
    assert not (root / "Model").exists()
    assert not (root / "Logs").exists()
    assert not (root / "gui_settings.json").exists()
    assert not (root / "experiments.json").exists()
    assert (root / "notes.txt").read_text(encoding="utf-8") == "user file"
    assert (outside / "keep.waj").exists()


def test_cleanup_rejects_paths_outside_wheelathlete_root(tmp_path: Path):
    with pytest.raises(ValueError, match="WheelAthlete-owned"):
        cleanup_wheelathlete_data(tmp_path / "not-the-app")


def test_portable_and_installed_root_detection_is_scoped(tmp_path: Path):
    portable = tmp_path / "PortableWheelAthlete"
    (portable / "_internal").mkdir(parents=True)
    exe = portable / "WheelAthlete.exe"
    daemon = portable / "_internal" / "WheelAthleteDaemon.exe"
    exe.touch()
    daemon.touch()

    assert portable_application_root(exe, frozen=True) == portable.resolve()
    (portable / "unins000.exe").touch()
    assert portable_application_root(exe, frozen=True) is None

    installed = tmp_path / "WheelAthlete"
    installed_exe = installed / "Application" / "WheelAthlete.exe"
    installed_exe.parent.mkdir(parents=True)
    installed_exe.touch()
    assert installed_application_data_root(installed_exe, frozen=True) == installed.resolve()
    assert installed_application_data_root(installed_exe, frozen=False) is None
    (installed_exe.parent / "_internal").mkdir()
    (installed_exe.parent / "_internal" / "WheelAthleteDaemon.exe").touch()
    (installed / "unins000.exe").touch()
    assert portable_application_root(installed_exe, frozen=True) is None


def test_portable_removal_waits_for_gui_process_exit(tmp_path: Path, monkeypatch):
    root = tmp_path / "PortableWheelAthlete"
    internal = root / "_internal"
    internal.mkdir(parents=True)
    (root / "WheelAthlete.exe").touch()
    (internal / "WheelAthleteDaemon.exe").touch()
    calls = []
    monkeypatch.setattr(cleanup.subprocess, "Popen", lambda *args, **kwargs: calls.append((args, kwargs)))

    cleanup.schedule_portable_application_removal(root, pid=4321)

    args, kwargs = calls[0]
    script = base64.b64decode(args[0][-1]).decode("utf-16-le")
    assert "Get-Process -Id $owner" in script
    assert "$owner = 4321" in script
    assert str(root.resolve()) in script
    assert "Remove-Item -LiteralPath $target -Recurse -Force" in script
    assert kwargs["creationflags"] & getattr(cleanup.subprocess, "CREATE_NO_WINDOW", 0)
