from __future__ import annotations

import hashlib
import json
from pathlib import Path

import pytest

import tools.pc_gui.update_service as update_service
from tools.pc_gui.update_service import (
    UpdateError,
    Version,
    WindowsArtifact,
    current_version,
    installer_command,
    parse_manifest,
    update_available,
)


def _manifest(*, version: str = "1.8.1", url: str | None = None) -> bytes:
    artifact = b"installer"
    value = {
        "schema": 1,
        "version": version,
        "channel": "stable",
        "release_url": f"https://github.com/NnopponS/WheelAthelse/releases/tag/v{version}",
        "notes": "Updater release",
        "platforms": {
            "windows": {
                "version": version,
                "url": url
                or f"https://github.com/NnopponS/WheelAthelse/releases/download/v{version}/WheelAthleteSetup-{version}.exe",
                "sha256": hashlib.sha256(artifact).hexdigest(),
                "size": len(artifact),
            }
        },
    }
    return json.dumps(value).encode("utf-8")


def test_semver_comparison() -> None:
    assert Version.parse("v1.8.1") == Version(1, 8, 1)
    assert update_available("1.8.0", "1.8.1")
    assert not update_available("1.8.1", "1.8.1")
    assert not update_available("1.9.0", "1.8.1")


def test_manifest_accepts_only_stable_repo_release_exe() -> None:
    manifest = parse_manifest(_manifest())
    assert manifest.version == "1.8.1"
    assert manifest.windows.size == len(b"installer")
    assert manifest.windows.url.endswith("WheelAthleteSetup-1.8.1.exe")

    with pytest.raises(UpdateError):
        parse_manifest(
            _manifest(
                url="https://evil.example/releases/download/v1.8.1/WheelAthleteSetup-1.8.1.exe"
            )
        )
    with pytest.raises(UpdateError):
        parse_manifest(
            _manifest(
                url="http://github.com/NnopponS/WheelAthelse/releases/download/v1.8.1/WheelAthleteSetup-1.8.1.exe"
            )
        )


def test_manifest_rejects_version_or_hash_mismatch() -> None:
    value = json.loads(_manifest())
    value["platforms"]["windows"]["version"] = "1.8.2"
    with pytest.raises(UpdateError):
        parse_manifest(json.dumps(value).encode())

    value = json.loads(_manifest())
    value["platforms"]["windows"]["sha256"] = "xyz"
    with pytest.raises(UpdateError):
        parse_manifest(json.dumps(value).encode())


def test_current_version_reads_repository_version(tmp_path: Path) -> None:
    repo_root = tmp_path / "applications" / "wheelathlete_windows"
    repo_root.mkdir(parents=True)
    (tmp_path / "VERSION").write_text("1.8.0\n", encoding="utf-8")
    assert current_version(repo_root) == "1.8.0"


def test_installer_command_is_silent_autoupdate(tmp_path: Path, monkeypatch) -> None:
    installer = tmp_path / "WheelAthleteSetup-1.8.1.exe"
    installer.write_bytes(b"installer")
    monkeypatch.setattr(
        "tools.pc_gui.update_service.updates_dir", lambda: tmp_path / "Updates"
    )
    command = installer_command(installer)
    assert command[0] == str(installer)
    assert "/VERYSILENT" in command
    assert "/CLOSEAPPLICATIONS" in command
    assert "/AUTOUPDATE=1" in command


def test_self_update_only_for_inno_installed_frozen_build(tmp_path: Path, monkeypatch) -> None:
    exe = tmp_path / "WheelAthlete.exe"
    exe.write_bytes(b"exe")
    monkeypatch.setattr(update_service.sys, "platform", "win32")
    monkeypatch.setattr(update_service.sys, "frozen", True, raising=False)
    monkeypatch.setattr(update_service.sys, "executable", str(exe))
    assert not update_service.self_update_supported()
    (tmp_path / "unins000.exe").write_bytes(b"uninstaller")
    assert update_service.self_update_supported()
