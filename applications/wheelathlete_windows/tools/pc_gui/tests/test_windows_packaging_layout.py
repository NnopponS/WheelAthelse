from pathlib import Path


WINDOWS_ROOT = Path(__file__).resolve().parents[3]
INSTALLER = WINDOWS_ROOT / "packaging" / "windows" / "installer.iss"
BUILD_SCRIPT = WINDOWS_ROOT / "packaging" / "windows" / "build_installer.bat"


def test_installer_uses_documents_root_and_preserves_research_data() -> None:
    text = INSTALLER.read_text(encoding="utf-8")
    assert "DefaultDirName={userdocs}\\{#MyAppName}" in text
    assert 'DestDir: "{app}\\Application"' in text
    assert 'DestDir: "{app}\\Model"' in text
    assert 'Name: "{app}\\PC Sessions"; Flags: uninsneveruninstall' in text
    assert 'Name: "{app}\\Model"; Flags: uninsneveruninstall' in text
    assert 'Type: filesandordirs; Name: "{app}\\Application"' in text
    assert 'Type: filesandordirs; Name: "{app}\\*"' not in text


def test_build_seeds_default_onnx_and_recipe_model() -> None:
    text = BUILD_SCRIPT.read_text(encoding="utf-8")
    assert "--collect-all onnxruntime" in text
    assert "wheelathlete_biwheel3d_m4.onnx" in text
    assert "BiWheel3D-XY-Yaw-current_best.json" in text
    assert "current_best_summary.json" not in text
