from __future__ import annotations

import base64
import os
import shutil
import subprocess
import sys
from pathlib import Path


_MANAGED_DIRECTORIES = (
    "PC Sessions",
    "Imported CSV",
    "Exports",
    "Model",
    "Logs",
    "Updates",
)
_MANAGED_FILES = ("gui_settings.json", "experiments.json")


def default_user_data_root() -> Path:
    return Path.home() / "Documents" / "WheelAthlete"


def _delete_managed_items(root: Path, *, include_settings: bool) -> list[str]:
    if root.is_symlink():
        raise ValueError("Refusing to clean a linked WheelAthlete data directory")
    root = root.resolve()
    if root.name.casefold() != "wheelathlete":
        raise ValueError("Refusing to clean outside a WheelAthlete-owned directory")
    removed: list[str] = []
    for name in _MANAGED_DIRECTORIES:
        item = root / name
        if item.parent != root or not (item.exists() or item.is_symlink()):
            continue
        if item.is_symlink() or not item.is_dir():
            item.unlink()
        else:
            shutil.rmtree(item)
        removed.append(name)
    if include_settings:
        for name in _MANAGED_FILES:
            item = root / name
            if item.parent == root and (item.exists() or item.is_symlink()):
                item.unlink()
                removed.append(name)
    return removed


def cleanup_wheelathlete_data(
    data_root: Path | str | None = None,
    install_root: Path | str | None = None,
) -> list[str]:
    """Delete only known WheelAthlete-owned data, leaving unrelated files alone."""
    data = Path(data_root) if data_root is not None else default_user_data_root()
    removed = [f"{data.name}/{name}" for name in _delete_managed_items(data, include_settings=True)]
    if install_root is not None:
        installed = Path(install_root)
        if installed.resolve() != data.resolve():
            removed.extend(
                f"{installed.name}/{name}"
                for name in _delete_managed_items(installed, include_settings=False)
            )
    return removed


def portable_application_root(
    executable: Path | str,
    *,
    frozen: bool,
) -> Path | None:
    exe = Path(executable)
    if (
        not frozen
        or exe.name.casefold() != "wheelathlete.exe"
        or exe.parent.name.casefold() == "application"
    ):
        return None
    root = exe.parent.resolve()
    if any(root.glob("unins*.exe")) or any(root.parent.glob("unins*.exe")):
        return None
    daemon = (root / "_internal" / "WheelAthleteDaemon.exe", root / "WheelAthleteDaemon.exe")
    if not exe.is_file() or not any(path.is_file() for path in daemon):
        return None
    return root


def installed_application_data_root(
    executable: Path | str,
    *,
    frozen: bool,
) -> Path | None:
    exe = Path(executable)
    if (
        not frozen
        or exe.name.casefold() != "wheelathlete.exe"
        or exe.parent.name.casefold() != "application"
    ):
        return None
    root = exe.parent.parent.resolve()
    if root.name.casefold() != "wheelathlete" or (root / "Application" / exe.name).resolve() != exe.resolve():
        return None
    return root


def schedule_portable_application_removal(
    root: Path | str,
    *,
    pid: int | None = None,
) -> None:
    target = Path(root)
    if target.is_symlink() or getattr(target, "is_junction", lambda: False)():
        raise ValueError("Refusing to remove a linked portable app directory")
    exe = target / "WheelAthlete.exe"
    if portable_application_root(exe, frozen=True) != target.resolve():
        raise ValueError("Refusing to remove a directory that is not a portable WheelAthlete app")
    quoted = str(target.resolve()).replace("'", "''")
    process_id = int(pid if pid is not None else os.getpid())
    script = (
        f"$target = '{quoted}'; $owner = {process_id}; $attempts = 0; "
        "while ((Get-Process -Id $owner -ErrorAction SilentlyContinue) -and $attempts -lt 200) { "
        "Start-Sleep -Milliseconds 300; $attempts++ }; "
        "if (-not (Get-Process -Id $owner -ErrorAction SilentlyContinue) -and "
        "(Test-Path -LiteralPath $target)) { "
        "Remove-Item -LiteralPath $target -Recurse -Force }"
    )
    encoded = base64.b64encode(script.encode("utf-16-le")).decode("ascii")
    flags = getattr(subprocess, "CREATE_NO_WINDOW", 0) | getattr(
        subprocess, "DETACHED_PROCESS", 0
    )
    subprocess.Popen(
        ["powershell.exe", "-NoProfile", "-NonInteractive", "-EncodedCommand", encoded],
        close_fds=True,
        creationflags=flags,
    )
