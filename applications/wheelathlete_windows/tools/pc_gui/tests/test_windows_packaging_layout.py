from pathlib import Path


WINDOWS_ROOT = Path(__file__).resolve().parents[3]
INSTALLER = WINDOWS_ROOT / "packaging" / "windows" / "installer.iss"
BUILD_SCRIPT = WINDOWS_ROOT / "packaging" / "windows" / "build_installer.bat"
STOP_DAEMON = WINDOWS_ROOT / "packaging" / "windows" / "stop_installed_daemon.ps1"
SIGN_ARTIFACT = WINDOWS_ROOT / "packaging" / "windows" / "sign_windows_artifact.ps1"
SIGN_TREE = WINDOWS_ROOT / "packaging" / "windows" / "sign_windows_tree.ps1"
RELEASE_METADATA = WINDOWS_ROOT / "packaging" / "windows" / "write_release_metadata.ps1"
RELEASE_WORKFLOW = WINDOWS_ROOT.parents[1] / ".github" / "workflows" / "release.yml"


def test_installer_uses_documents_root_and_preserves_research_data() -> None:
    text = INSTALLER.read_text(encoding="utf-8")
    assert "DefaultDirName={userdocs}\\{#MyAppName}" in text
    assert 'DestDir: "{app}\\Application"' in text
    assert 'DestDir: "{app}\\Model"' in text
    assert 'Name: "{app}\\PC Sessions"; Flags: uninsneveruninstall' in text
    assert 'Name: "{app}\\Model"; Flags: uninsneveruninstall' in text
    model_line = next(
        line for line in text.splitlines() if 'DestDir: "{app}\\Model"' in line
    )
    assert "onlyifdoesntexist" in model_line
    assert "uninsneveruninstall" in model_line
    assert 'Type: filesandordirs; Name: "{app}\\Application"' in text
    assert 'Type: filesandordirs; Name: "{app}\\*"' not in text


def test_build_seeds_default_onnx_and_recipe_model() -> None:
    text = BUILD_SCRIPT.read_text(encoding="utf-8")
    assert "--collect-all onnxruntime" not in text
    assert "wheelathlete_biwheel3d_m4.onnx" in text
    assert "BiWheel3D-XY-Yaw-current_best.json" in text
    assert "current_best_summary.json" not in text


def test_install_and_uninstall_stop_only_the_installed_daemon() -> None:
    installer = INSTALLER.read_text(encoding="utf-8")
    helper = STOP_DAEMON.read_text(encoding="utf-8")
    assert "PrepareToInstall" in installer
    assert "InitializeUninstall" in installer
    assert "stop_installed_daemon.ps1" in installer
    assert "ExecutablePath" in helper
    assert "OrdinalIgnoreCase" in helper
    assert 'Send-Command $writer $reader "shutdown"' in helper
    assert 'Send-Command $writer $reader "end_record"' in helper
    assert "recording_starting" in helper


def test_build_signs_and_verifies_every_distributed_executable() -> None:
    build = BUILD_SCRIPT.read_text(encoding="utf-8")
    installer = INSTALLER.read_text(encoding="utf-8")
    signer = SIGN_ARTIFACT.read_text(encoding="utf-8")
    tree = SIGN_TREE.read_text(encoding="utf-8")
    metadata = RELEASE_METADATA.read_text(encoding="utf-8")
    workflow = RELEASE_WORKFLOW.read_text(encoding="utf-8")
    assert "WHEELATHLETE_SIGN_CERT_SHA1" in build
    assert "WHEELATHLETE_TIMESTAMP_URL" in build
    assert "WHEELATHLETE_SIGN_CERT_SUBJECT" in build
    assert "sign_windows_tree.ps1" in build
    assert "/DMySignedBuild=1" in build
    assert "/Swheelathlete=" in build
    assert "signing-report.json" in build
    assert "write_release_metadata.ps1" in build
    assert "signtool.exe" in signer
    assert "verify /pa /all" in signer
    assert "RSACertificateExtensions" in signer
    assert "1.3.6.1.5.5.7.3.3" in signer
    assert "TimestampCertificate" in signer
    assert '@(".exe", ".dll", ".pyd", ".ps1")' in tree
    assert "SignedUninstaller=yes" in installer
    assert "SignTool=wheelathlete" in installer
    assert "Get-AuthenticodeSignature" in metadata
    assert "TimestampCertificate" in metadata
    assert "Get-ReleaseRelativePath" in metadata
    assert "[IO.Path]::GetRelativePath" not in metadata
    assert "ExpectedSignerSubject" in metadata
    assert '"WheelAthlete\\WheelAthlete.exe"' in metadata
    assert '"WheelAthlete\\_internal\\WheelAthleteDaemon.exe"' in metadata
    assert '"WheelAthleteSetup-$Version.exe"' in metadata
    assert "Get-FileHash" in metadata
    assert "WHEELATHLETE_SIGN_CERT_SUBJECT" in workflow
    assert "contents: read" in workflow
    assert "contents: write" in workflow
    assert "public_release_ready" in workflow
    assert "Release workflow must be dispatched on exact tag" in workflow
