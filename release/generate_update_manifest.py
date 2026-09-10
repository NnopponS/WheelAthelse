from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

REPO = "NnopponS/WheelAthelse"
SCHEMA_VERSION = 1


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def artifact_record(path: Path, *, url: str) -> dict[str, Any]:
    if not path.is_file():
        raise FileNotFoundError(path)
    return {
        "url": url,
        "sha256": sha256_file(path),
        "size": path.stat().st_size,
    }


def build_manifest(
    *,
    version: str,
    windows_installer: Path,
    android_apk: Path | None = None,
    android_build: int | None = None,
    notes: str = "",
    ios_url: str = "",
    repo: str = REPO,
    channel: str = "stable",
) -> dict[str, Any]:
    tag = f"v{version}"
    base = f"https://github.com/{repo}/releases/download/{tag}"
    release_page = f"https://github.com/{repo}/releases/tag/{tag}"
    platforms: dict[str, Any] = {
        "windows": {
            "version": version,
            **artifact_record(
                windows_installer,
                url=f"{base}/{windows_installer.name}",
            ),
        }
    }
    if android_apk is not None:
        if android_build is None:
            raise ValueError("android_build is required when android_apk is provided")
        platforms["android"] = {
            "version": version,
            "build": int(android_build),
            **artifact_record(android_apk, url=f"{base}/{android_apk.name}"),
        }
    if ios_url.strip() or android_apk is not None:
        platforms["ios"] = {
            "version": version,
            "url": ios_url.strip() or release_page,
            "store_managed": True,
        }
    manifest = {
        "schema": SCHEMA_VERSION,
        "version": version,
        "channel": channel,
        "release_url": release_page,
        "notes": notes.strip(),
        "platforms": platforms,
    }
    return manifest


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate the WheelAthlete cross-platform update manifest."
    )
    parser.add_argument("--version", required=True)
    parser.add_argument("--android", type=Path)
    parser.add_argument("--android-build", type=int)
    parser.add_argument("--windows", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--repo", default=REPO)
    parser.add_argument("--channel", default="stable")
    parser.add_argument("--notes", default="")
    parser.add_argument("--ios-url", default="")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    manifest = build_manifest(
        version=args.version,
        android_apk=args.android,
        windows_installer=args.windows,
        android_build=args.android_build,
        notes=args.notes,
        ios_url=args.ios_url,
        repo=args.repo,
        channel=args.channel,
    )
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(args.out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
