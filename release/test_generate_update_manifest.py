from __future__ import annotations

import hashlib
import tempfile
import unittest
from pathlib import Path

from release.generate_update_manifest import build_manifest


class UpdateManifestTests(unittest.TestCase):
    def test_manifest_contains_verified_platform_artifacts(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            apk = root / "WheelAthlete-Android-1.8.1.apk"
            exe = root / "WheelAthleteSetup-1.8.1.exe"
            apk.write_bytes(b"apk-bytes")
            exe.write_bytes(b"installer-bytes")

            manifest = build_manifest(
                version="1.8.1",
                android_apk=apk,
                windows_installer=exe,
                android_build=10,
                notes="Updater release",
            )

            self.assertEqual(manifest["schema"], 1)
            self.assertEqual(manifest["version"], "1.8.1")
            self.assertEqual(manifest["channel"], "stable")
            android = manifest["platforms"]["android"]
            windows = manifest["platforms"]["windows"]
            self.assertEqual(android["build"], 10)
            self.assertEqual(android["size"], len(b"apk-bytes"))
            self.assertEqual(
                android["sha256"], hashlib.sha256(b"apk-bytes").hexdigest()
            )
            self.assertTrue(android["url"].endswith(apk.name))
            self.assertEqual(windows["size"], len(b"installer-bytes"))
            self.assertTrue(windows["url"].endswith(exe.name))
            self.assertTrue(manifest["platforms"]["ios"]["store_managed"])

    def test_windows_only_manifest_omits_unavailable_mobile_platforms(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            installer = Path(tmp) / "WheelAthleteSetup-1.8.2.exe"
            installer.write_bytes(b"signed-installer")
            manifest = build_manifest(
                version="1.8.2",
                windows_installer=installer,
                notes="Windows-first release",
            )
            self.assertEqual(set(manifest["platforms"]), {"windows"})
            self.assertTrue(manifest["platforms"]["windows"]["is_signed"])

    def test_unsigned_windows_manifest_sets_is_signed_false(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            installer = Path(tmp) / "WheelAthleteSetup-1.8.2.exe"
            installer.write_bytes(b"unsigned-installer")
            manifest = build_manifest(
                version="1.8.2",
                windows_installer=installer,
                notes="Community release",
                is_signed=False,
            )
            self.assertEqual(set(manifest["platforms"]), {"windows"})
            self.assertFalse(manifest["platforms"]["windows"]["is_signed"])


if __name__ == "__main__":
    unittest.main()
