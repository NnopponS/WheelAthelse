from __future__ import annotations

import hashlib
import json
import os
import subprocess
import sys
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

MANIFEST_URL = (
    "https://github.com/NnopponS/WheelAthelse/releases/latest/download/latest.json"
)
REPO_PATH_PREFIX = "/NnopponS/WheelAthelse/"
REPO_RELEASE_PREFIX = f"{REPO_PATH_PREFIX}releases/download/"
SCHEMA_VERSION = 1


class UpdateError(RuntimeError):
    pass


@dataclass(frozen=True)
class Version:
    major: int
    minor: int
    patch: int

    @classmethod
    def parse(cls, value: str) -> "Version":
        raw = value.strip()
        if raw.lower().startswith("v"):
            raw = raw[1:]
        core = raw.split("+", 1)[0].split("-", 1)[0]
        parts = core.split(".")
        if len(parts) != 3 or any(not part.isdigit() for part in parts):
            raise UpdateError(f"Invalid semantic version: {value!r}")
        return cls(*(int(part) for part in parts))

    def __lt__(self, other: object) -> bool:
        if not isinstance(other, Version):
            return NotImplemented
        return (self.major, self.minor, self.patch) < (
            other.major,
            other.minor,
            other.patch,
        )


@dataclass(frozen=True)
class WindowsArtifact:
    version: str
    url: str
    sha256: str
    size: int


@dataclass(frozen=True)
class UpdateManifest:
    version: str
    channel: str
    release_url: str
    notes: str
    windows: WindowsArtifact


def _validate_https_repo_url(
    url: str,
    *,
    suffix: str | None = None,
    release_download: bool = False,
) -> None:
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme.lower() != "https":
        raise UpdateError("Update URLs must use HTTPS")
    if parsed.hostname != "github.com":
        raise UpdateError("Update host must be github.com")
    required_prefix = REPO_RELEASE_PREFIX if release_download else REPO_PATH_PREFIX
    if not parsed.path.startswith(required_prefix):
        raise UpdateError("Update URL is outside the WheelAthelse GitHub repository")
    if suffix is not None and not parsed.path.lower().endswith(suffix.lower()):
        raise UpdateError(f"Update artifact must end with {suffix}")


def parse_manifest(payload: bytes) -> UpdateManifest:
    try:
        value = json.loads(payload.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise UpdateError("Update manifest is not valid UTF-8 JSON") from exc
    if not isinstance(value, dict) or value.get("schema") != SCHEMA_VERSION:
        raise UpdateError("Unsupported update manifest schema")
    version = str(value.get("version", "")).strip()
    Version.parse(version)
    if value.get("channel") != "stable":
        raise UpdateError("Only the stable update channel is accepted")
    platforms = value.get("platforms")
    windows = platforms.get("windows") if isinstance(platforms, dict) else None
    if not isinstance(windows, dict):
        raise UpdateError("Update manifest is missing the Windows artifact")
    artifact_version = str(windows.get("version", "")).strip()
    if artifact_version != version:
        raise UpdateError("Windows artifact version does not match manifest version")
    url = str(windows.get("url", "")).strip()
    _validate_https_repo_url(url, suffix=".exe", release_download=True)
    sha = str(windows.get("sha256", "")).strip().lower()
    if len(sha) != 64 or any(ch not in "0123456789abcdef" for ch in sha):
        raise UpdateError("Windows artifact SHA-256 is invalid")
    size = windows.get("size")
    if not isinstance(size, int) or size <= 0:
        raise UpdateError("Windows artifact size is invalid")
    release_url = str(value.get("release_url", "")).strip()
    if release_url:
        _validate_https_repo_url(release_url)
    return UpdateManifest(
        version=version,
        channel="stable",
        release_url=release_url,
        notes=str(value.get("notes", "")).strip(),
        windows=WindowsArtifact(
            version=artifact_version,
            url=url,
            sha256=sha,
            size=size,
        ),
    )


def current_version(repo_root: Path | None = None) -> str:
    override = os.environ.get("WHEELATHLETE_VERSION", "").strip()
    if override:
        Version.parse(override)
        return override
    candidates: list[Path] = []
    if getattr(sys, "frozen", False):
        meipass = getattr(sys, "_MEIPASS", "")
        if meipass:
            candidates.append(Path(meipass) / "VERSION")
        candidates.append(Path(sys.executable).resolve().parent / "VERSION")
        candidates.append(Path(sys.executable).resolve().parent / "_internal" / "VERSION")
    if repo_root is not None:
        candidates.extend(
            [
                repo_root / "VERSION",
                repo_root.parent.parent / "VERSION",
            ]
        )
    for candidate in candidates:
        if candidate.is_file():
            value = candidate.read_text(encoding="utf-8").strip()
            Version.parse(value)
            return value
    return "0.0.0"


def update_available(current: str, remote: str) -> bool:
    return Version.parse(current) < Version.parse(remote)


def fetch_manifest(
    url: str = MANIFEST_URL,
    *,
    timeout_s: float = 10.0,
    opener: Callable[..., object] | None = None,
) -> UpdateManifest:
    _validate_https_repo_url(url)
    request = urllib.request.Request(
        url,
        headers={"User-Agent": "WheelAthlete-Windows-Updater/1"},
    )
    open_fn = opener or urllib.request.urlopen
    try:
        response = open_fn(request, timeout=timeout_s)
        with response:  # type: ignore[attr-defined]
            payload = response.read(1024 * 1024)  # type: ignore[attr-defined]
    except Exception as exc:
        raise UpdateError(f"Could not check for updates: {exc}") from exc
    return parse_manifest(payload)


def updates_dir() -> Path:
    root = Path.home() / "Documents" / "WheelAthlete" / "Updates"
    root.mkdir(parents=True, exist_ok=True)
    return root


def download_update(
    artifact: WindowsArtifact,
    *,
    destination_dir: Path | None = None,
    timeout_s: float = 30.0,
    progress: Callable[[int, int], None] | None = None,
) -> Path:
    _validate_https_repo_url(
        artifact.url,
        suffix=".exe",
        release_download=True,
    )
    root = destination_dir or updates_dir()
    root.mkdir(parents=True, exist_ok=True)
    final_path = root / f"WheelAthleteSetup-{artifact.version}.exe"
    part_path = final_path.with_suffix(final_path.suffix + ".part")
    part_path.unlink(missing_ok=True)
    digest = hashlib.sha256()
    total = 0
    request = urllib.request.Request(
        artifact.url,
        headers={"User-Agent": "WheelAthlete-Windows-Updater/1"},
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout_s) as response:
            with part_path.open("wb") as output:
                while True:
                    chunk = response.read(1024 * 256)
                    if not chunk:
                        break
                    output.write(chunk)
                    digest.update(chunk)
                    total += len(chunk)
                    if total > artifact.size:
                        raise UpdateError("Downloaded installer is larger than the manifest size")
                    if progress is not None:
                        progress(total, artifact.size)
        if total != artifact.size:
            raise UpdateError(
                f"Downloaded installer size mismatch: expected {artifact.size}, got {total}"
            )
        actual = digest.hexdigest()
        if actual.lower() != artifact.sha256.lower():
            raise UpdateError("Downloaded installer SHA-256 does not match the manifest")
        part_path.replace(final_path)
        return final_path
    except Exception:
        part_path.unlink(missing_ok=True)
        raise


def self_update_supported() -> bool:
    if sys.platform != "win32" or not bool(getattr(sys, "frozen", False)):
        return False
    # Only an Inno-installed build replaces itself automatically. A portable
    # ZIP is also PyInstaller-frozen, but it has no stable install location or
    # uninstaller and therefore only exposes the GitHub release page.
    exe_dir = Path(sys.executable).resolve().parent
    return any(exe_dir.glob("unins*.exe"))


def installer_command(installer: Path) -> list[str]:
    if not installer.is_file():
        raise UpdateError(f"Installer not found: {installer}")
    return [
        str(installer),
        "/VERYSILENT",
        "/SUPPRESSMSGBOXES",
        "/NORESTART",
        "/CLOSEAPPLICATIONS",
        "/AUTOUPDATE=1",
        f"/LOG={updates_dir() / 'installer.log'}",
    ]


def launch_installer(installer: Path) -> subprocess.Popen[bytes]:
    if not self_update_supported():
        raise UpdateError(
            "Self-update installation is only enabled in the packaged Windows application"
        )
    command = installer_command(installer)
    return subprocess.Popen(  # noqa: S603
        command,
        close_fds=True,
        creationflags=getattr(subprocess, "DETACHED_PROCESS", 0),
    )
