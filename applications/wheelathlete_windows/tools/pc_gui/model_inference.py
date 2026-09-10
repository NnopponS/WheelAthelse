from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any


ACCEL_G_TO_MS2 = 9.80665
TARGET_SAMPLE_HZ = 100
SAMPLES_PER_MODEL_STEP = 5
MIN_MODEL_STEPS = 40
BIWHEEL3D_FEATURE_DIM = 90
CURRENT_BEST_WHEEL_RADIUS_M = 0.30
CURRENT_BEST_TRACK_WIDTH_M = 0.52
CURRENT_BEST_KEY = "biwheel3d:xy_yaw_current_best"
CURRENT_BEST_RECIPE_NAME = "BiWheel3D-XY-Yaw-current_best.json"
MODEL_BUNDLE_MANIFEST = "wheelathlete-model.json"
SUPPORTED_BUNDLE_INPUTS = {
    "recipe": ("biwheel3d_dual_hub_v1", 60, ("numpy",)),
    "onnx": ("biwheel3d_features_v1", BIWHEEL3D_FEATURE_DIM, ("numpy", "onnxruntime")),
    "pytorch_residual": ("biwheel3d_residual_features_v1", 88, ("numpy", "torch")),
    "pytorch_residual_slalom_course": (
        "biwheel3d_residual_features_v1",
        88,
        ("numpy", "torch"),
    ),
    "unified_hybrid": ("biwheel3d_dual_hub_v1", 60, ("numpy", "scipy", "biwheel3d")),
}
SUPPORTED_OUTPUT_UNITS = {
    "x_m": "m",
    "y_m": "m",
    "signed_speed_mps": "m/s",
    "speed_mps": "m/s",
    "longitudinal_accel_mps2": "m/s2",
    "yaw_rad": "rad",
    "yaw_rate_radps": "rad/s",
    "lateral_accel_mps2": "m/s2",
    "speed_change_mps2": "m/s2",
}


class ModelInferenceError(RuntimeError):
    """Raised when a recording cannot be prepared or a trajectory model cannot run safely."""


@dataclass(frozen=True, slots=True)
class ModelSpec:
    key: str
    label: str
    checkpoint: Path
    description: str
    kind: str = "recipe"
    bundled: bool = False
    course_config: Path | None = None
    model_version: str = "legacy"
    preprocessing_id: str = "legacy"
    required_sensor_roles: tuple[str, ...] = ("L", "R")
    output_capabilities: tuple[tuple[str, str], ...] = ()
    runtime_requirements: tuple[str, ...] = ()
    experimental: bool = False
    bundle_manifest: Path | None = None


def _short_label(value: str, fallback: str) -> str:
    label = " ".join(value.split()).strip() or fallback
    return label if len(label) <= 32 else label[:29].rstrip() + "..."


def _bundle_path(root: Path, value: Any, field: str) -> Path:
    if not isinstance(value, str) or not value.strip():
        raise ModelInferenceError(f"Model bundle {field} must be a relative file path.")
    relative = Path(value)
    if relative.is_absolute():
        raise ModelInferenceError(f"Model bundle {field} must stay inside the bundle.")
    resolved = (root / relative).resolve()
    try:
        resolved.relative_to(root)
    except ValueError as exc:
        raise ModelInferenceError(f"Model bundle {field} escapes the bundle directory.") from exc
    if not resolved.is_file():
        raise ModelInferenceError(f"Model bundle {field} was not found: {value}")
    return resolved


def model_bundle_spec(manifest_path: Path) -> ModelSpec:
    """Validate one portable model bundle before exposing it to the runtime."""
    manifest = manifest_path.expanduser().resolve()
    if not manifest.is_file() or manifest.name.lower() != MODEL_BUNDLE_MANIFEST:
        raise ModelInferenceError(f"Choose a {MODEL_BUNDLE_MANIFEST} bundle manifest.")
    try:
        payload = json.loads(manifest.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ModelInferenceError(f"Model bundle manifest is not valid JSON: {manifest}") from exc
    if not isinstance(payload, dict):
        raise ModelInferenceError("Model bundle manifest must contain a JSON object.")
    version = payload.get("schema_version")
    if isinstance(version, bool) or version != 1:
        raise ModelInferenceError(f"Unsupported model bundle schema_version: {version!r}; expected 1.")

    model_id = payload.get("model_id")
    display_name = payload.get("display_name")
    model_version = payload.get("model_version")
    if not isinstance(model_id, str) or not model_id.strip():
        raise ModelInferenceError("Model bundle model_id must be a non-empty string.")
    if not isinstance(display_name, str) or not display_name.strip():
        raise ModelInferenceError("Model bundle display_name must be a non-empty string.")
    if not isinstance(model_version, str) or not model_version.strip():
        raise ModelInferenceError("Model bundle model_version must be a non-empty string.")

    runtime = payload.get("runtime")
    if not isinstance(runtime, dict):
        raise ModelInferenceError("Model bundle runtime must be an object.")
    kind = runtime.get("kind")
    if kind not in SUPPORTED_BUNDLE_INPUTS:
        supported = ", ".join(SUPPORTED_BUNDLE_INPUTS)
        raise ModelInferenceError(f"Unsupported model bundle runtime kind {kind!r}; supported: {supported}.")
    preprocessing_id, expected_dim, expected_requirements = SUPPORTED_BUNDLE_INPUTS[kind]
    requirements = runtime.get("requires")
    if requirements != list(expected_requirements):
        raise ModelInferenceError(
            f"Model bundle runtime.requires for {kind} must be {list(expected_requirements)!r}."
        )

    preprocessing = payload.get("preprocessing")
    if not isinstance(preprocessing, dict):
        raise ModelInferenceError("Model bundle preprocessing must be an object.")
    if preprocessing.get("id") != preprocessing_id:
        raise ModelInferenceError(
            f"Model bundle preprocessing.id for {kind} must be {preprocessing_id!r}."
        )
    if preprocessing.get("sample_rate_hz") != TARGET_SAMPLE_HZ:
        raise ModelInferenceError(f"Model bundle sample_rate_hz must be {TARGET_SAMPLE_HZ}.")
    feature_dim = preprocessing.get("feature_dim")
    if isinstance(feature_dim, bool) or feature_dim != expected_dim:
        raise ModelInferenceError(f"Model bundle feature_dim for {kind} must be {expected_dim}.")

    roles = payload.get("required_sensor_roles")
    if roles != ["L", "R"]:
        raise ModelInferenceError("This app supports model bundles requiring sensor roles ['L', 'R'].")
    raw_outputs = payload.get("outputs")
    if not isinstance(raw_outputs, list) or not raw_outputs:
        raise ModelInferenceError("Model bundle outputs must be a non-empty array.")
    outputs: list[tuple[str, str]] = []
    for output in raw_outputs:
        if not isinstance(output, dict):
            raise ModelInferenceError("Each model bundle output must be an object.")
        name, unit = output.get("name"), output.get("unit")
        if SUPPORTED_OUTPUT_UNITS.get(name) != unit:
            raise ModelInferenceError(f"Unsupported model bundle output or unit: {name!r} / {unit!r}.")
        if (name, unit) in outputs:
            raise ModelInferenceError(f"Duplicate model bundle output: {name}.")
        outputs.append((name, unit))
    if not {"x_m", "y_m"}.issubset(name for name, _unit in outputs):
        raise ModelInferenceError("Model bundle outputs must include x_m and y_m.")

    root = manifest.parent.resolve()
    checkpoint = _bundle_path(root, payload.get("artifact"), "artifact")
    expected_suffixes = {
        "recipe": {".json"},
        "onnx": {".onnx"},
        "pytorch_residual": {".pt", ".pth"},
        "pytorch_residual_slalom_course": {".pt", ".pth"},
        "unified_hybrid": {".json"},
    }[kind]
    if checkpoint.suffix.lower() not in expected_suffixes:
        raise ModelInferenceError(f"Model bundle artifact extension is incompatible with {kind}.")
    if kind == "recipe":
        _recipe_spec(checkpoint, strict=True)
    course_config = None
    if kind == "pytorch_residual_slalom_course":
        course_config = _bundle_path(root, payload.get("course_config"), "course_config")

    experimental = payload.get("experimental")
    if not isinstance(experimental, bool):
        raise ModelInferenceError("Model bundle experimental must be true or false.")
    description = payload.get("description")
    if description is not None and not isinstance(description, str):
        raise ModelInferenceError("Model bundle description must be a string when provided.")
    return ModelSpec(
        key=model_id.strip(),
        label=_short_label(display_name, model_id),
        checkpoint=checkpoint,
        description=(description or f"Portable {kind} model bundle.").strip(),
        kind=kind,
        bundled=True,
        course_config=course_config,
        model_version=model_version.strip(),
        preprocessing_id=preprocessing_id,
        required_sensor_roles=("L", "R"),
        output_capabilities=tuple(outputs),
        runtime_requirements=expected_requirements,
        experimental=experimental,
        bundle_manifest=manifest,
    )


def model_library_root() -> Path:
    """Return the user-editable WheelAthlete model library."""
    override = os.environ.get("WHEELATHLETE_MODEL_DIR", "").strip()
    if override:
        return Path(override).expanduser().resolve()
    base = (Path.home() / "Documents" / "WheelAthlete").resolve()
    model_sub = (base / "Model").resolve()
    if model_sub.is_dir():
        return model_sub
    return base


def _runtime_root() -> Path:
    return Path(__file__).resolve().parent / "biwheel3d_runtime"


def _bundled_current_best_recipe() -> Path:
    return _runtime_root() / CURRENT_BEST_RECIPE_NAME


def _recipe_spec(
    path: Path, *, bundled: bool = False, strict: bool = True
) -> ModelSpec | None:
    resolved = path.expanduser().resolve()
    try:
        payload = json.loads(resolved.read_text(encoding="utf-8"))
    except Exception as exc:
        if strict:
            raise ModelInferenceError(
                f"Could not read BiWheel3D recipe: {resolved}"
            ) from exc
        return None
    if (
        not isinstance(payload, dict)
        or payload.get("model_type") != "biwheel3d_xy_yaw_recipe"
    ):
        if strict:
            raise ModelInferenceError(
                "Recipe JSON is not a supported BiWheel3D XY + Yaw model recipe. "
                "Choose an ONNX model or a JSON file with model_type='biwheel3d_xy_yaw_recipe'."
            )
        return None
    key = str(payload.get("model_id") or f"recipe:{resolved}")
    label = (
        "Kinematic Trajectory (XY + Yaw)"
        if key == CURRENT_BEST_KEY
        or raw_label in {
            "Classical v1",
            "BiWheel3D XY + Yaw - current_best",
            "BiWheel3D-XY-Yaw-current_best",
            "BiWheel3D Classical Kinematic Baseline [Classical v1]",
            "BiWheel3D Classical Kinematic Baseline (XY + Yaw) [v1]",
            "Kinematic Trajectory (XY + Yaw)",
        }
        else raw_label
    )
    description = str(
        payload.get("description")
        or payload.get("recipe")
        or "BiWheel3D XY + Yaw recipe"
    )
    return ModelSpec(
        key=key,
        label=label,
        checkpoint=resolved,
        description=description,
        kind="recipe",
        bundled=bundled,
        model_version="1",
        preprocessing_id="biwheel3d_dual_hub_v1",
        output_capabilities=(
            ("x_m", "m"),
            ("y_m", "m"),
            ("signed_speed_mps", "m/s"),
            ("yaw_rad", "rad"),
            ("yaw_rate_radps", "rad/s"),
        ),
        runtime_requirements=("numpy",),
    )


def custom_model_spec(checkpoint: Path) -> ModelSpec:
    """Build a validated model selection from a user-selected file."""
    resolved = checkpoint.expanduser().resolve()
    if not resolved.is_file():
        raise ModelInferenceError(f"Model file was not found: {resolved}")
    suffix = resolved.suffix.lower()
    if suffix == ".onnx":
        stem = resolved.stem.lower()
        label = (
            "Mobile M4"
            if "biwheel3d" in stem and "m4" in stem
            else _short_label(resolved.stem, "ONNX model")
        )
        return ModelSpec(
            key=f"onnx:{resolved}",
            label=label,
            checkpoint=resolved,
            description=(
                "ONNX trajectory model using the BiWheel3D 90-feature input contract. "
                "Runs locally with ONNX Runtime on CPU."
            ),
            kind="onnx",
            model_version="M4" if "biwheel3d" in stem and "m4" in stem else "legacy",
            preprocessing_id="biwheel3d_features_v1",
            output_capabilities=(("x_m", "m"), ("y_m", "m")),
            runtime_requirements=("numpy", "onnxruntime"),
        )
    if suffix == ".json":
        if resolved.name.lower() == MODEL_BUNDLE_MANIFEST:
            return model_bundle_spec(resolved)
        try:
            payload = json.loads(resolved.read_text(encoding="utf-8"))
            if isinstance(payload, dict) and payload.get("model_type") == "unified_hybrid":
                return ModelSpec(
                    key=str(payload.get("model_id") or f"unified_hybrid:{resolved}"),
                    label="Hybrid v1",
                    checkpoint=resolved,
                    description=str(
                        payload.get("description")
                        or "Unified 5-method hybrid wheelchair estimator combining 3D camber kinematics, multi-scale shock features, biomechanical phase InEKF (ZUPT/ZARU), RTS smoothing, and skid-steer ICR adjustment."
                    ),
                    kind="unified_hybrid",
                    bundled=False,
                    model_version="1",
                    preprocessing_id="biwheel3d_dual_hub_v1",
                    output_capabilities=(
                        ("x_m", "m"),
                        ("y_m", "m"),
                        ("signed_speed_mps", "m/s"),
                        ("yaw_rad", "rad"),
                        ("yaw_rate_radps", "rad/s"),
                    ),
                    runtime_requirements=("numpy", "scipy", "biwheel3d"),
                    experimental=True,
                )
        except Exception:
            pass
        spec = _recipe_spec(resolved, bundled=False, strict=True)
        assert spec is not None
        return spec
    if suffix in {".pt", ".pth"}:
        stem = resolved.stem.lower()
        label = (
            "Residual v1"
            if "residual" in stem or stem == "best"
            else _short_label(resolved.stem, "PyTorch model")
        )
        return ModelSpec(
            key=f"pytorch_residual:{resolved}",
            label=label,
            checkpoint=resolved,
            description=(
                "Research-only C3D-supervised residual BiGRU. Corrects signed speed and yaw rate "
                "on top of the zero-delay dual-hub physics baseline. Requires local PyTorch; "
                "it does not replace the frozen production recipe."
            ),
            kind="pytorch_residual",
            model_version="1",
            preprocessing_id="biwheel3d_residual_features_v1",
            output_capabilities=(
                ("x_m", "m"),
                ("y_m", "m"),
                ("signed_speed_mps", "m/s"),
                ("yaw_rad", "rad"),
                ("yaw_rate_radps", "rad/s"),
            ),
            runtime_requirements=("numpy", "torch"),
            experimental=True,
        )
    raise ModelInferenceError(
        "Choose a BiWheel3D .onnx, .pt/.pth research checkpoint, or supported .json recipe."
    )


def _candidate_model_dirs() -> list[Path]:
    roots = [model_library_root()]
    if not os.environ.get("WHEELATHLETE_MODEL_DIR", "").strip():
        doc_root = (Path.home() / "Documents" / "WheelAthlete").resolve()
        model_sub = (doc_root / "Model").resolve()
        roots.extend([model_sub, doc_root])
    if getattr(sys, "frozen", False):
        exe_dir = Path(sys.executable).resolve().parent
        roots.extend([exe_dir / "Model", exe_dir.parent / "Model", exe_dir])
    unique: list[Path] = []
    seen: set[Path] = set()
    for root in roots:
        try:
            resolved = root.resolve()
        except OSError:
            resolved = root
        if resolved not in seen:
            seen.add(resolved)
            unique.append(resolved)
    return unique


def _research_registry_specs(repo_root: Path) -> list[ModelSpec]:
    """Discover optional local-only BiWheel3D research artifacts from its registry.

    Installed/clean application checkouts do not require the friend research repo.
    """
    research_root = (Path(repo_root) / "BiWheel3D").resolve()
    registry = research_root / "registry" / "models.json"
    if not registry.is_file():
        return []
    try:
        payload = json.loads(registry.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return []
    specs: list[ModelSpec] = []
    for entry in payload.get("models", []):
        if (
            not isinstance(entry, dict)
            or entry.get("status") == "frozen_application_baseline"
        ):
            continue
        manifest_rel = entry.get("manifest")
        if not isinstance(manifest_rel, str):
            continue
        try:
            manifest_path = (research_root / manifest_rel).resolve()
            manifest_path.relative_to(research_root)
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            registry_kind = str(entry.get("kind") or "")
            if registry_kind == "unified_hybrid":
                config_rel = (manifest.get("artifacts") or {}).get("config", {}).get("path")
                config_path = (research_root / config_rel).resolve() if config_rel else manifest_path
                spec = ModelSpec(
                    key=str(entry.get("model_id") or "biwheel3d:unified_hybrid_v1"),
                    label="Hybrid v1",
                    checkpoint=config_path,
                    description=str(
                        entry.get("description")
                        or manifest.get("description")
                        or "Unified 5-method hybrid wheelchair estimator combining 3D camber kinematics, multi-scale shock features, biomechanical phase InEKF (ZUPT/ZARU), RTS smoothing, and skid-steer ICR adjustment."
                    )
                    + " Discovered from the local BiWheel3D research registry.",
                    kind="unified_hybrid",
                    bundled=False,
                    model_version="1",
                    preprocessing_id="biwheel3d_dual_hub_v1",
                    output_capabilities=(
                        ("x_m", "m"),
                        ("y_m", "m"),
                        ("signed_speed_mps", "m/s"),
                        ("yaw_rad", "rad"),
                        ("yaw_rate_radps", "rad/s"),
                    ),
                    experimental=True,
                )
            elif registry_kind == "pytorch_residual_slalom_course":
                artifact_rel = manifest["artifacts"]["pytorch"]["path"]
                artifact = (research_root / artifact_rel).resolve()
                artifact.relative_to(research_root)
                course_rel = manifest["artifacts"]["course_config"]["path"]
                course_config = (research_root / course_rel).resolve()
                course_config.relative_to(research_root)
                if not course_config.is_file():
                    continue
                spec = ModelSpec(
                    key=str(
                        entry.get("model_id") or f"pytorch_slalom_course:{artifact}"
                    ),
                    label="Slalom v1",
                    checkpoint=artifact,
                    description=(
                        "Research-only PyTorch residual v1 with an explicit fixed-course Slalom "
                        "heading/position constraint. Non-Slalom sessions are an exact no-op; "
                        "the adapter never reads C3D at inference."
                    ),
                    kind="pytorch_residual_slalom_course",
                    bundled=False,
                    course_config=course_config,
                    model_version="1",
                    preprocessing_id="biwheel3d_residual_features_v1",
                    output_capabilities=(
                        ("x_m", "m"),
                        ("y_m", "m"),
                        ("signed_speed_mps", "m/s"),
                        ("yaw_rad", "rad"),
                        ("yaw_rate_radps", "rad/s"),
                    ),
                    experimental=True,
                )
            else:
                artifact_rel = manifest["artifacts"]["pytorch"]["path"]
                artifact = (research_root / artifact_rel).resolve()
                artifact.relative_to(research_root)
                base_spec = custom_model_spec(artifact)
                spec = ModelSpec(
                    key=base_spec.key,
                    label="Residual v1",
                    checkpoint=base_spec.checkpoint,
                    description=base_spec.description
                    + " Discovered from the local BiWheel3D research registry.",
                    kind=base_spec.kind,
                    bundled=False,
                    model_version=base_spec.model_version,
                    preprocessing_id=base_spec.preprocessing_id,
                    required_sensor_roles=base_spec.required_sensor_roles,
                    output_capabilities=base_spec.output_capabilities,
                    runtime_requirements=base_spec.runtime_requirements,
                    experimental=True,
                )
        except (
            KeyError,
            OSError,
            ValueError,
            json.JSONDecodeError,
            ModelInferenceError,
        ):
            continue
        specs.append(spec)
    return specs


def active_research_dataset_root(repo_root: Path) -> Path:
    """Return the canonical active supervised dataset path when locally available."""
    research_root = (Path(repo_root) / "BiWheel3D").resolve()
    registry = research_root / "registry" / "datasets.json"
    if registry.is_file():
        try:
            payload = json.loads(registry.read_text(encoding="utf-8"))
            entry = next(
                item
                for item in payload.get("datasets", [])
                if item.get("status") == "active_supervised"
            )
            candidate = (research_root / str(entry["path"])).resolve()
            candidate.relative_to((research_root / "data").resolve())
            if candidate.is_dir():
                return candidate
        except (OSError, ValueError, KeyError, StopIteration, json.JSONDecodeError):
            pass
    return research_root / "data"


def _same_checkpoint_content(left: Path, right: Path) -> bool:
    """Deduplicate local/library copies of the same experimental artifact."""
    try:
        if left.stat().st_size != right.stat().st_size:
            return False
        return (
            hashlib.sha256(left.read_bytes()).digest()
            == hashlib.sha256(right.read_bytes()).digest()
        )
    except OSError:
        return False


def discover_compatible_models(repo_root: Path) -> list[ModelSpec]:
    """Discover built-in, user-library, and optional local research models."""
    discovered: list[ModelSpec] = []
    seen_keys: set[str] = set()
    seen_paths: set[Path] = set()

    for root in _candidate_model_dirs():
        if not root.is_dir():
            continue
        for manifest in sorted(root.glob(f"*/{MODEL_BUNDLE_MANIFEST}")):
            try:
                spec = model_bundle_spec(manifest)
            except ModelInferenceError:
                continue
            if spec.key in seen_keys or spec.checkpoint in seen_paths:
                continue
            discovered.append(spec)
            seen_keys.add(spec.key)
            seen_paths.add(spec.checkpoint)

    # Prefer a user-visible copy of the current recipe when setup has seeded it.
    for root in _candidate_model_dirs():
        if not root.is_dir():
            continue
        for path in sorted(root.glob("*.json"), key=lambda item: item.name.lower()):
            spec = _recipe_spec(path, bundled=False, strict=False)
            if spec is None or spec.key in seen_keys:
                continue
            discovered.append(spec)
            seen_keys.add(spec.key)
            seen_paths.add(spec.checkpoint)

    bundled_recipe = _bundled_current_best_recipe()
    if CURRENT_BEST_KEY not in seen_keys and bundled_recipe.is_file():
        spec = _recipe_spec(bundled_recipe, bundled=True, strict=False)
        if spec is not None:
            discovered.insert(0, spec)
            seen_keys.add(spec.key)
            seen_paths.add(spec.checkpoint)

    learned_specs: list[ModelSpec] = []
    for root in _candidate_model_dirs():
        if not root.is_dir():
            continue
        paths = [*root.glob("*.onnx"), *root.glob("*.pt"), *root.glob("*.pth")]
        for path in sorted(paths, key=lambda item: item.name.lower()):
            try:
                resolved = path.resolve()
            except OSError:
                continue
            if resolved in seen_paths:
                continue
            try:
                spec = custom_model_spec(resolved)
            except ModelInferenceError:
                continue
            learned_specs.append(spec)
            seen_paths.add(resolved)

    for spec in _research_registry_specs(repo_root):
        if spec.checkpoint in seen_paths or spec.key in seen_keys:
            continue
        if spec.kind == "pytorch_residual" and any(
            existing.kind == "pytorch_residual"
            and _same_checkpoint_content(existing.checkpoint, spec.checkpoint)
            for existing in learned_specs
        ):
            continue
        learned_specs.append(spec)
        seen_paths.add(spec.checkpoint)
        seen_keys.add(spec.key)

    # Keep the calibrated current-best recipe first, then browseable learned models.
    return discovered + learned_specs


def model_runtime_status(repo_root: Path) -> tuple[bool, str]:
    """Check the common MODEL runtime without importing heavy optional providers."""
    del repo_root
    if importlib.util.find_spec("numpy") is None:
        return False, "NumPy is required for BiWheel3D trajectory analysis."
    runtime = _runtime_root()
    if not (runtime / "yaw_ab.py").is_file():
        return False, "Bundled BiWheel3D XY + Yaw runtime is missing."
    if not _bundled_current_best_recipe().is_file():
        return False, "Bundled BiWheel3D current_best recipe is missing."
    return True, f"Model library: {model_library_root()}"


def model_spec_runtime_status(spec: ModelSpec) -> tuple[bool, str]:
    """Validate dependencies for the selected model without executing inference."""
    if importlib.util.find_spec("numpy") is None:
        return False, "NumPy is required for trajectory analysis."
    if not spec.checkpoint.is_file():
        return False, f"Model file not found: {spec.checkpoint}"
    for requirement in spec.runtime_requirements:
        if importlib.util.find_spec(requirement) is None:
            return False, f"This model requires the Python package {requirement}."
    if spec.kind == "onnx":
        if importlib.util.find_spec("onnxruntime") is None:
            return False, "ONNX Runtime is required for this model."
        return True, "ONNX Runtime CPU provider ready."
    if spec.kind == "recipe":
        if not (_runtime_root() / "yaw_ab.py").is_file():
            return False, "BiWheel3D XY + Yaw runtime is missing."
        return True, "BiWheel3D XY + Yaw recipe ready."
    if spec.kind in {"pytorch_residual", "pytorch_residual_slalom_course"}:
        if importlib.util.find_spec("torch") is None:
            return (
                False,
                "PyTorch is required for this experimental residual checkpoint.",
            )
        if not (_runtime_root() / "yaw_ab.py").is_file():
            return False, "BiWheel3D physics runtime is missing."
        if spec.kind == "pytorch_residual_slalom_course":
            if spec.course_config is None or not spec.course_config.is_file():
                return False, "Slalom course adapter config is missing."
            try:
                course_meta = json.loads(spec.course_config.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError):
                return False, "Slalom course adapter config is invalid."
            if int(course_meta.get("schema_version", 1)) == 2 and importlib.util.find_spec("scipy") is None:
                return False, "SciPy is required for experimental Slalom course adapter v2."
            version = int(course_meta.get("schema_version", 1))
            return True, f"Experimental PyTorch + Slalom course adapter v{version} ready."
        return (
            True,
            "Experimental PyTorch residual runtime ready (CPU/GPU selected by local PyTorch).",
        )
    if spec.kind == "unified_hybrid":
        if importlib.util.find_spec("scipy") is None:
            return False, "SciPy is required for Unified Hybrid trajectory optimization."
        return True, "Unified Hybrid InEKF + RTS runtime ready."
    return False, f"Unsupported model kind: {spec.kind}"


def prepare_dual_windows(
    session_data: dict[str, Any],
    *,
    target_hz: int = TARGET_SAMPLE_HZ,
) -> tuple[Any, dict[str, Any]]:
    from .analysis_timing import AnalysisInputError, prepare_windows

    try:
        return prepare_windows(session_data, target_hz=target_hz)
    except (AnalysisInputError, ValueError, TypeError) as exc:
        raise ModelInferenceError(str(exc)) from exc


def extract_biwheel3d_features(windows: Any) -> Any:
    """Return the exact BiWheel3D protocol-v10b `(T, 90)` feature tensor."""
    try:
        import numpy as np
        from .biwheel3d_runtime.imu_frame import (
            canonicalize_dual_windows,
            demod_rim_accel,
        )
    except ImportError as exc:  # pragma: no cover - runtime guard
        raise ModelInferenceError(
            "BiWheel3D feature extraction dependencies are unavailable."
        ) from exc

    w = canonicalize_dual_windows(np.asarray(windows, dtype=np.float32))
    if w.ndim != 3 or w.shape[1] != SAMPLES_PER_MODEL_STEP or w.shape[2] != 12:
        raise ModelInferenceError(
            f"Expected BiWheel3D windows shaped (T,5,12), got {w.shape}."
        )
    if w.shape[0] < MIN_MODEL_STEPS:
        raise ModelInferenceError(
            f"BiWheel3D requires at least {MIN_MODEL_STEPS} model steps."
        )

    flat = w.reshape(w.shape[0], 60)
    mu = w.mean(axis=1)
    dt = 0.05
    radius_m = CURRENT_BEST_WHEEL_RADIUS_M
    track_m = CURRENT_BEST_TRACK_WIDTH_M
    g = ACCEL_G_TO_MS2
    lgz, rgz = mu[:, 5], mu[:, 11]
    kin = np.stack(
        [
            0.5 * (lgz - rgz) * dt,
            0.5 * (lgz + rgz) * dt,
            (radius_m / track_m) * (rgz - lgz) * dt,
            (radius_m / track_m) * (lgz - rgz) * dt,
            np.abs(lgz) * dt,
            np.abs(rgz) * dt,
        ],
        axis=-1,
    ).astype(np.float32)

    lf, ll = demod_rim_accel(mu[:, 0], mu[:, 1], mu[:, 5], dt=dt)
    rf, rl = demod_rim_accel(mu[:, 6], mu[:, 7], mu[:, 11], dt=dt)
    fwd = 0.5 * (lf + rf)
    lat = 0.5 * (ll + rl)
    az_lp = 0.5 * (mu[:, 2] + mu[:, 8])
    az_lp = np.convolve(
        az_lp.astype(np.float64), np.ones(11) / 11.0, mode="same"
    ).astype(np.float32)
    phi_r = np.arcsin(np.clip(rf / g, -1.0, 1.0)).astype(np.float32)
    phi_l = np.arcsin(np.clip(lf / g, -1.0, 1.0)).astype(np.float32)
    phi_mean = np.arcsin(np.clip(fwd / g, -1.0, 1.0)).astype(np.float32)
    phi_abs = np.abs(phi_mean).astype(np.float32)
    pitch = np.arctan2(-fwd, np.maximum(np.abs(az_lp), 1.0)).astype(np.float32)
    grav = np.stack(
        [lf, ll, rf, rl, fwd, lat, az_lp, phi_r, phi_l, phi_mean, phi_abs, pitch],
        axis=-1,
    ).astype(np.float32)
    features = np.concatenate([flat, mu, kin, grav], axis=-1).astype(np.float32)
    if features.shape[1] != BIWHEEL3D_FEATURE_DIM or not np.all(np.isfinite(features)):
        raise ModelInferenceError(
            f"BiWheel3D feature extraction produced invalid shape {features.shape}."
        )
    return features


def _load_recipe(path: Path) -> dict[str, Any]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        raise ModelInferenceError(f"Could not read BiWheel3D recipe: {path}") from exc
    if (
        not isinstance(payload, dict)
        or payload.get("model_type") != "biwheel3d_xy_yaw_recipe"
    ):
        raise ModelInferenceError(f"Unsupported BiWheel3D recipe: {path}")
    return payload


def _build_runtime_trial(
    *,
    windows: Any,
    session_data: dict[str, Any],
    Trial: Any,
    TrialMeta: Any,
    np: Any,
    wheel_radius_m: float,
    track_width_m: float,
) -> Any:
    n_steps = int(windows.shape[0])
    n_raw = n_steps * SAMPLES_PER_MODEL_STEP
    left_windows = np.asarray(windows[:, :, :6], dtype=np.float32)
    right_windows = np.asarray(windows[:, :, 6:], dtype=np.float32)
    left_raw = left_windows.reshape(n_raw, 6)
    right_raw = right_windows.reshape(n_raw, 6)

    t_imu = np.arange(n_raw, dtype=np.float64) / float(TARGET_SAMPLE_HZ)
    t_gt = 0.02 + np.arange(n_steps, dtype=np.float64) * 0.05

    session_id = str(session_data.get("session_id") or "wheelathlete_session")
    topic = str(session_data.get("topic") or "")
    maneuver = str(
        session_data.get("maneuver") or session_data.get("protocol") or "unknown"
    )
    athlete = str(session_data.get("athlete") or "")
    duration_s = float(n_raw / TARGET_SAMPLE_HZ)
    meta = TrialMeta(
        trial_id=session_id,
        split="runtime",
        condition=topic or "runtime",
        maneuver=maneuver,
        R=wheel_radius_m,
        L_hub=track_width_m,
        alpha=0.0,
        L_floor=track_width_m,
        imu_hz=TARGET_SAMPLE_HZ,
        gt_hz=TARGET_SAMPLE_HZ // SAMPLES_PER_MODEL_STEP,
        sync_ratio=SAMPLES_PER_MODEL_STEP,
        duration_s=duration_s,
        n_gt=n_steps,
        n_imu=n_raw,
        has_gt=False,
        athlete=athlete,
    )
    zeros_xyz = np.zeros((n_steps, 3), dtype=np.float32)
    zeros_1d = np.zeros(n_steps, dtype=np.float32)
    return Trial(
        meta=meta,
        t_gt=t_gt,
        xyz=zeros_xyz.copy(),
        xyz_left=zeros_xyz.copy(),
        xyz_right=zeros_xyz.copy(),
        angles=zeros_xyz.copy(),
        v=zeros_1d.copy(),
        omega=zeros_1d.copy(),
        theta_left=zeros_1d.copy(),
        theta_right=zeros_1d.copy(),
        imu_left_windows=left_windows,
        imu_right_windows=right_windows,
        t_imu=t_imu,
        imu_left=left_raw,
        imu_right=right_raw,
    )


def _run_recipe_model(
    spec: ModelSpec, windows: Any, session_data: dict[str, Any], np: Any
) -> dict[str, Any]:
    try:
        from .biwheel3d_runtime.schema import Trial, TrialMeta
        from .biwheel3d_runtime.yaw_ab import (
            DEFAULT_CHASSIS_YAW_SCALE,
            DEFAULT_YAW_DELAY_FRAMES,
            odom_gyro_only,
        )
    except ImportError as exc:
        raise ModelInferenceError(
            "BiWheel3D XY + Yaw runtime could not be imported."
        ) from exc

    recipe = _load_recipe(spec.checkpoint)
    wheel_radius_m = float(recipe.get("wheel_radius_m") or CURRENT_BEST_WHEEL_RADIUS_M)
    track_width_m = float(recipe.get("track_width_m") or CURRENT_BEST_TRACK_WIDTH_M)
    gyro_scale = float(recipe.get("gyro_scale") or 1.10)
    chassis_yaw_scale = float(
        recipe.get("chassis_yaw_scale") or DEFAULT_CHASSIS_YAW_SCALE
    )
    yaw_delay_frames = int(recipe.get("yaw_delay_frames", DEFAULT_YAW_DELAY_FRAMES))
    yaw_delay_pad = str(recipe.get("yaw_delay_pad") or "burst")
    yaw_source = str(recipe.get("yaw_source") or "auto")
    align = bool(recipe.get("align", True))
    trial = _build_runtime_trial(
        windows=windows,
        session_data=session_data,
        Trial=Trial,
        TrialMeta=TrialMeta,
        np=np,
        wheel_radius_m=wheel_radius_m,
        track_width_m=track_width_m,
    )
    try:
        pred = odom_gyro_only(
            trial,
            gyro_scale=gyro_scale,
            chassis_yaw_scale=chassis_yaw_scale,
            yaw_delay_frames=yaw_delay_frames,
            yaw_delay_pad=yaw_delay_pad,
            yaw_source=yaw_source,
            align=align,
        )
    except Exception as exc:
        raise ModelInferenceError(
            f"BiWheel3D XY + Yaw trajectory failed: {exc}"
        ) from exc

    xyz = np.asarray(pred.get("xyz"), dtype=np.float64)
    angles = np.asarray(pred.get("angles"), dtype=np.float64)
    if (
        xyz.ndim != 2
        or xyz.shape[0] < 2
        or xyz.shape[1] < 2
        or not np.all(np.isfinite(xyz[:, :2]))
    ):
        raise ModelInferenceError("BiWheel3D returned an invalid 2D trajectory.")
    expected_steps = int(windows.shape[0])
    velocity = np.asarray(pred.get("v"), dtype=np.float64)
    rate = np.asarray(pred.get("yaw_rate"), dtype=np.float64)
    if (
        xyz.shape != (expected_steps, 3)
        or angles.shape != (expected_steps, 3)
        or velocity.shape != (expected_steps,)
        or rate.shape != (expected_steps,)
        or not all(np.isfinite(a).all() for a in (xyz, angles, velocity, rate))
    ):
        raise ModelInferenceError(
            "Recipe kinematic outputs have inconsistent shape or non-finite values"
        )
    # Preserve estimator unwrapped orientation; never infer heading from XY.
    yaw = angles[:, 1]
    net_yaw_deg = float(np.degrees(yaw[-1] - yaw[0]))
    return {
        "xy": xyz[:, :2],
        "signed_speed_mps": velocity.tolist(),
        "yaw_rad": yaw.tolist(),
        "yaw_rate_radps": rate.tolist(),
        "xy_frame": "first_travel_display" if align else "initial_chair_heading",
        "yaw_frame": "initial_chair_heading",
        "net_yaw_deg": net_yaw_deg,
        "yaw_source": str(pred.get("yaw_source") or yaw_source),
        "yaw_delay_frames": int(pred.get("yaw_delay_frames", yaw_delay_frames)),
        "yaw_delay_pad": str(pred.get("yaw_delay_pad", yaw_delay_pad)),
        "yaw_delay_bursts": int(pred.get("yaw_delay_bursts") or 0),
        "gyro_scale": gyro_scale,
        "chassis_yaw_scale": chassis_yaw_scale,
        "wheel_radius_m": wheel_radius_m,
        "track_width_m": track_width_m,
        "recipe": str(recipe.get("recipe") or spec.label),
        "runtime_source": "biwheel3d_xy_yaw_recipe",
    }


def _run_pytorch_residual_model(
    spec: ModelSpec, windows: Any, session_data: dict[str, Any], np: Any, *, include_internal: bool = False
) -> dict[str, Any]:
    """Run the research residual-v1 checkpoint without changing production defaults.

    The checkpoint is allowed only as an explicit experimental selection. Its 88-feature
    input reproduces the research trainer: flattened dual windows, mean/std channels,
    frozen-current rates, and zero-delay center-mean research rates.
    """
    try:
        import torch
        from torch import nn
        from .biwheel3d_runtime.imu_frame import canonicalize_dual_windows
        from .biwheel3d_runtime.schema import Trial, TrialMeta
        from .biwheel3d_runtime.yaw_ab import odom_gyro_only
    except ImportError as exc:
        raise ModelInferenceError(
            "PyTorch residual runtime dependencies are unavailable."
        ) from exc

    try:
        checkpoint = torch.load(
            str(spec.checkpoint), map_location="cpu", weights_only=True
        )
    except Exception as exc:
        raise ModelInferenceError(
            f"Could not load PyTorch residual checkpoint: {exc}"
        ) from exc
    if (
        not isinstance(checkpoint, dict)
        or checkpoint.get("feature_version") != "torch_residual_v1"
    ):
        raise ModelInferenceError(
            "Unsupported PyTorch checkpoint: expected feature_version='torch_residual_v1'."
        )
    model_cfg = checkpoint.get("model") or {}
    normalizer = checkpoint.get("normalizer") or {}
    recipe = checkpoint.get("baseline_recipe") or {}
    try:
        input_size = int(model_cfg["input_size"])
        hidden_size = int(model_cfg["hidden_size"])
        num_layers = int(model_cfg["num_layers"])
        dropout = float(model_cfg["dropout"])
        bidirectional = bool(model_cfg["bidirectional"])
        mean = np.asarray(normalizer["mean"], dtype=np.float32)
        scale = np.asarray(normalizer["scale"], dtype=np.float32)
        residual_scale = np.asarray(normalizer["residual_scale"], dtype=np.float32)
    except (KeyError, TypeError, ValueError) as exc:
        raise ModelInferenceError(
            "PyTorch residual checkpoint metadata is incomplete."
        ) from exc
    if (
        input_size != 88
        or mean.shape != (88,)
        or scale.shape != (88,)
        or residual_scale.shape != (2,)
    ):
        raise ModelInferenceError(
            "PyTorch residual checkpoint has an incompatible feature/normalizer shape."
        )
    if not all(np.isfinite(a).all() for a in (mean, scale, residual_scale)) or np.any(
        scale <= 0
    ):
        raise ModelInferenceError(
            "PyTorch residual checkpoint normalization is invalid."
        )

    wheel_radius_m = float(recipe.get("wheel_radius_m") or CURRENT_BEST_WHEEL_RADIUS_M)
    track_width_m = float(recipe.get("track_width_m") or CURRENT_BEST_TRACK_WIDTH_M)
    gyro_scale = float(recipe.get("gyro_scale", 1.0))
    yaw_scale = float(recipe.get("yaw_scale", 1.0))
    chassis_yaw_scale = float(recipe.get("chassis_yaw_scale", 1.0))
    yaw_delay_frames = int(recipe.get("yaw_delay_frames", 27))
    yaw_delay_pad = str(recipe.get("yaw_delay_pad", "burst"))
    yaw_source = str(recipe.get("yaw_source", "auto"))
    trial = _build_runtime_trial(
        windows=windows,
        session_data=session_data,
        Trial=Trial,
        TrialMeta=TrialMeta,
        np=np,
        wheel_radius_m=wheel_radius_m,
        track_width_m=track_width_m,
    )
    canonical = canonicalize_dual_windows(np.asarray(windows, dtype=np.float32)).astype(
        np.float32
    )
    if canonical.ndim != 3 or canonical.shape[1:] != (5, 12):
        raise ModelInferenceError(
            f"PyTorch residual expected (T,5,12) windows, got {canonical.shape}."
        )

    def rates(*, research: bool) -> Any:
        pred = odom_gyro_only(
            trial,
            gyro_scale=gyro_scale,
            yaw_scale=yaw_scale,
            chassis_yaw_scale=chassis_yaw_scale,
            yaw_delay_frames=0 if research else yaw_delay_frames,
            yaw_delay_pad="none" if research else yaw_delay_pad,
            yaw_source=yaw_source,
            align=False,
        )
        yaw_rate = np.asarray(pred["yaw_rate"], dtype=np.float32)
        if research:
            channels = pred.get("channels") or {}
            omega_l = np.asarray(channels.get("omega_l"), dtype=np.float32)
            omega_r = np.asarray(channels.get("omega_r"), dtype=np.float32)
            if omega_l.shape != yaw_rate.shape or omega_r.shape != yaw_rate.shape:
                raise ModelInferenceError(
                    "Research physics channels have incompatible shape."
                )
            speed = wheel_radius_m * gyro_scale * 0.5 * (omega_l + omega_r)
        else:
            speed = np.asarray(pred["v"], dtype=np.float32)
        return np.column_stack([speed, yaw_rate]).astype(np.float32)

    current_rates = rates(research=False)
    research_rates = rates(research=True)
    flat = canonical.reshape(len(canonical), 60)
    channel_mean = canonical.mean(axis=1)
    channel_std = canonical.std(axis=1)
    features = np.concatenate(
        [flat, channel_mean, channel_std, current_rates, research_rates], axis=1
    ).astype(np.float32)
    if features.shape != (len(canonical), 88) or not np.isfinite(features).all():
        raise ModelInferenceError(
            f"PyTorch residual features are invalid: {features.shape}."
        )
    normalized = ((features - mean) / scale).astype(np.float32)

    class ResidualBiGRU(nn.Module):
        def __init__(self) -> None:
            super().__init__()
            self.gru = nn.GRU(
                input_size=input_size,
                hidden_size=hidden_size,
                num_layers=num_layers,
                batch_first=True,
                bidirectional=bidirectional,
                dropout=dropout if num_layers > 1 else 0.0,
            )
            width = hidden_size * (2 if bidirectional else 1)
            self.head = nn.Sequential(
                nn.LayerNorm(width),
                nn.Linear(width, hidden_size),
                nn.SiLU(),
                nn.Dropout(dropout),
                nn.Linear(hidden_size, 2),
            )
            self.register_buffer(
                "residual_scale",
                torch.as_tensor(residual_scale.reshape(1, 1, 2), dtype=torch.float32),
            )

        def forward(self, normalized_features, base_rates):
            hidden, _ = self.gru(normalized_features)
            return base_rates + self.head(hidden) * self.residual_scale

    model = ResidualBiGRU()
    try:
        model.load_state_dict(checkpoint["state_dict"], strict=True)
    except Exception as exc:
        raise ModelInferenceError(
            f"PyTorch residual checkpoint weights are incompatible: {exc}"
        ) from exc
    model.eval()
    with torch.no_grad():
        x = torch.from_numpy(normalized).unsqueeze(0)
        base = torch.from_numpy(research_rates).unsqueeze(0)
        predicted_tensor = model(x, base)[0].cpu()
        # Match the research checkpoint's float32 midpoint integration exactly.
        speed_tensor = predicted_tensor[:, 0]
        rate_tensor = predicted_tensor[:, 1]
        yaw_tensor = torch.zeros_like(rate_tensor)
        xy_tensor = torch.zeros(
            (len(predicted_tensor), 2), dtype=predicted_tensor.dtype
        )
        if len(predicted_tensor) > 1:
            dpsi = 0.5 * (rate_tensor[1:] + rate_tensor[:-1]) * 0.05
            yaw_tensor[1:] = torch.cumsum(dpsi, dim=0)
            vmid = 0.5 * (speed_tensor[1:] + speed_tensor[:-1])
            heading_mid = yaw_tensor[:-1] + 0.5 * dpsi
            xy_tensor[1:, 0] = torch.cumsum(vmid * torch.cos(heading_mid) * 0.05, dim=0)
            xy_tensor[1:, 1] = torch.cumsum(vmid * torch.sin(heading_mid) * 0.05, dim=0)
        predicted = predicted_tensor.numpy()
        yaw = yaw_tensor.numpy()
        xy = xy_tensor.numpy()
    if predicted.shape != (len(canonical), 2) or not all(
        np.isfinite(a).all() for a in (predicted, yaw, xy)
    ):
        raise ModelInferenceError(
            "PyTorch residual model returned invalid rates or trajectory."
        )

    speed = predicted[:, 0]
    rate = predicted[:, 1]
    selection = checkpoint.get("selection") or {}
    result = {
        "xy": xy,
        "signed_speed_mps": speed.tolist(),
        "yaw_rad": yaw.tolist(),
        "yaw_rate_radps": rate.tolist(),
        "xy_frame": "initial_chair_heading",
        "yaw_frame": "initial_chair_heading",
        "net_yaw_deg": float(np.degrees(yaw[-1] - yaw[0])) if len(yaw) else 0.0,
        "yaw_source": "pytorch_residual_on_zero_delay_physics",
        "yaw_delay_frames": 0,
        "yaw_delay_pad": "none",
        "yaw_delay_bursts": 0,
        "gyro_scale": gyro_scale,
        "chassis_yaw_scale": chassis_yaw_scale,
        "wheel_radius_m": wheel_radius_m,
        "track_width_m": track_width_m,
        "recipe": f"PyTorch residual v1 (best epoch {selection.get('best_epoch', 'unknown')})",
        "runtime_source": "pytorch_residual_v1_experimental",
        "feature_dim": 88,
        "warnings": [
            "Experimental PyTorch residual v1; checkpoint selected on historical validation and not promoted as production current_best.",
            "Zero-delay center-mean physics is used only inside this experimental model path.",
        ],
    }
    if include_internal:
        result["_research_rates"] = research_rates.copy()
        result["_current_rates"] = current_rates.copy()
    return result


def _session_matches_slalom_course(
    session_data: dict[str, Any], config: dict[str, Any]
) -> bool:
    allowed = {
        str(value).strip().casefold()
        for value in config.get("applies_to_conditions", [])
    }
    observed = {
        str(session_data.get(key) or "").strip().casefold()
        for key in ("condition", "topic", "maneuver")
        if str(session_data.get(key) or "").strip()
    }
    return bool(allowed & observed)


def _run_pytorch_slalom_course_model(
    spec: ModelSpec,
    windows: Any,
    session_data: dict[str, Any],
    np: Any,
) -> dict[str, Any]:
    """Apply an explicit fixed-course Slalom adapter after frozen residual v1."""
    if spec.course_config is None or not spec.course_config.is_file():
        raise ModelInferenceError("Slalom course adapter config is missing.")
    try:
        config_bytes = spec.course_config.read_bytes()
        config = json.loads(config_bytes.decode("utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ModelInferenceError(f"Could not read Slalom course config: {exc}") from exc
    if not isinstance(config, dict) or not bool(config.get("never_use_c3d_at_inference")):
        raise ModelInferenceError("Slalom course config must explicitly forbid C3D at inference.")
    version = int(config.get("schema_version", 1))
    config_sha256 = hashlib.sha256(config_bytes).hexdigest()
    base = _run_pytorch_residual_model(
        spec, windows, session_data, np, include_internal=version >= 3
    )
    if not _session_matches_slalom_course(session_data, config):
        base.pop("_research_rates", None)
        base.pop("_current_rates", None)
        base["runtime_source"] = "pytorch_residual_v1_slalom_course_noop"
        base["course_constraint"] = {
            "adapter_version": version,
            "applied": False,
            "reason": "session is not explicitly labeled as an allowed Slalom condition",
            "course_config_sha256": config_sha256,
            "uses_c3d_at_inference": False,
        }
        base.setdefault("warnings", []).append(
            "Slalom course adapter selected but not applied because this session is not explicitly labeled SL/slalom."
        )
        return base
    rates = np.column_stack([
        np.asarray(base["signed_speed_mps"], dtype=np.float32),
        np.asarray(base["yaw_rate_radps"], dtype=np.float32),
    ]).astype(np.float32)
    try:
        if version >= 3:
            from .slalom_course_v3 import apply_slalom_calibrated_v3, integrate_rates_float32
            research_rates = np.asarray(base.pop("_research_rates"), dtype=np.float32)
            current_rates = np.asarray(base.pop("_current_rates"), dtype=np.float32)
            adapted = apply_slalom_calibrated_v3(rates, research_rates, current_rates, config)
            final_rates = adapted.rates
            metadata = {key: (list(value) if isinstance(value, tuple) else value)
                        for key, value in adapted.__dict__.items() if key != "rates"}
        elif version == 2:
            from .slalom_course_v2 import apply_slalom_course_v2
            from .slalom_course import integrate_rates_float32
            adapted = apply_slalom_course_v2(rates, config)
            final_rates = adapted.rates
            metadata = dict(adapted.metadata)
        else:
            from .slalom_course import apply_slalom_course_constraints, integrate_rates_float32
            adapted = apply_slalom_course_constraints(rates, config)
            final_rates = adapted.rates
            metadata = {
                "adapter_version": 1,
                "applied": bool(adapted.heading_closure or adapted.position_closure),
                "heading_closure": adapted.heading_closure,
                "position_closure": adapted.position_closure,
                "turn_count": adapted.turn_count,
                "removed_net_heading_deg": adapted.removed_net_heading_deg,
                "speed_correction_rms_mps": adapted.speed_correction_rms_mps,
                "speed_correction_max_abs_mps": adapted.speed_correction_max_abs_mps,
                "endpoint_before_m": adapted.endpoint_before_m,
                "endpoint_after_m": adapted.endpoint_after_m,
                "uses_c3d_at_inference": False,
            }
        xy, yaw = integrate_rates_float32(final_rates)
    except (ImportError, RuntimeError, KeyError, TypeError, ValueError, np.linalg.LinAlgError) as exc:
        raise ModelInferenceError(f"Slalom course constraint v{version} failed: {exc}") from exc
    metadata["adapter_version"] = version
    metadata["course_config_sha256"] = config_sha256
    metadata["uses_c3d_at_inference"] = False
    base.update({
        "xy": xy,
        "signed_speed_mps": final_rates[:, 0].astype(float).tolist(),
        "yaw_rad": yaw.astype(float).tolist(),
        "yaw_rate_radps": final_rates[:, 1].astype(float).tolist(),
        "net_yaw_deg": float(np.degrees(yaw[-1] - yaw[0])) if len(yaw) else 0.0,
        "recipe": f"PyTorch residual v1 + Slalom course constraint v{version}",
        "runtime_source": f"pytorch_residual_v1_slalom_course_v{version}_experimental",
        "course_constraint": metadata,
    })
    if version >= 3:
        if metadata.get("calibration_applied"):
            warning = "Train-calibrated Slalom v3 applied: frozen linear yaw/speed residual calibration plus sign-aware fixed-course closure."
        else:
            warning = "Slalom v3 learned calibration was skipped by its out-of-distribution guard; sign-aware fixed-course closure used the raw residual-v1 rates."
    elif version == 2:
        warning = "Experimental Slalom v2 applied; this historical optimizer is retained for audit and is not the recommended candidate."
    else:
        warning = "Protocol-aware Slalom course constraint applied: start/end heading is declared equal by the test protocol."
    base.setdefault("warnings", []).extend([
        warning,
        "Any near-zero endpoint is partly imposed by the declared fixed-course protocol and is not independent unconstrained odometry evidence.",
    ])
    return base


def _run_onnx_model(spec: ModelSpec, windows: Any, np: Any) -> dict[str, Any]:
    try:
        import onnxruntime as ort
        from .biwheel3d_runtime.infer_eval import align_first_travel_xy
    except ImportError as exc:
        raise ModelInferenceError("ONNX Runtime is required to run this model.") from exc

    features = extract_biwheel3d_features(windows)
    try:
        session = ort.InferenceSession(str(spec.checkpoint), providers=["CPUExecutionProvider"])
        inputs = session.get_inputs()
        outputs = session.get_outputs()
        if len(inputs) != 1:
            raise ModelInferenceError("ONNX model must expose exactly one BiWheel3D feature input.")
        input_meta = inputs[0]
        if input_meta.name != "features":
            raise ModelInferenceError(f"ONNX input must be named 'features', got '{input_meta.name}'.")
        if not outputs:
            raise ModelInferenceError("ONNX model exposes no outputs.")
        output_name = "xy" if any(item.name == "xy" for item in outputs) else outputs[0].name
        raw = session.run([output_name], {input_meta.name: features[None, :, :].astype(np.float32)})[0]
    except ModelInferenceError:
        raise
    except Exception as exc:
        raise ModelInferenceError(f"ONNX model inference failed: {exc}") from exc

    xy = np.asarray(raw, dtype=np.float64)
    if xy.ndim == 3 and xy.shape[0] == 1:
        xy = xy[0]
    if xy.ndim != 2 or xy.shape[0] != windows.shape[0] or xy.shape[1] < 2:
        raise ModelInferenceError(f"ONNX model returned unexpected XY shape {xy.shape}.")
    xy = xy[:, :2]
    if not np.all(np.isfinite(xy)):
        raise ModelInferenceError("ONNX model returned non-finite XY values.")
    xyz = np.zeros((xy.shape[0], 3), dtype=np.float32)
    xyz[:, :2] = xy.astype(np.float32)
    aligned_xyz, _ = align_first_travel_xy(xyz, None)
    return {
        "xy": np.asarray(aligned_xyz[:, :2], dtype=np.float64),
        "xy_frame": "first_travel_display",
        "yaw_frame": "unavailable",
        "net_yaw_deg": None,
        "yaw_source": "XY output only",
        "yaw_delay_frames": 0,
        "yaw_delay_pad": "none",
        "yaw_delay_bursts": 0,
        "gyro_scale": None,
        "chassis_yaw_scale": None,
        "wheel_radius_m": CURRENT_BEST_WHEEL_RADIUS_M,
        "track_width_m": CURRENT_BEST_TRACK_WIDTH_M,
        "recipe": "BiWheel3D learned ONNX trajectory model",
        "runtime_source": "onnxruntime_cpu",
        "feature_dim": BIWHEEL3D_FEATURE_DIM,
    }


def _run_unified_hybrid_model(
    spec: ModelSpec,
    windows: Any,
    session_data: dict[str, Any],
    np: Any,
) -> dict[str, Any]:
    """Run the 5-method Unified Hybrid Estimator (PINN-InEKF + ICR + RTS)."""
    try:
        from .biwheel3d_runtime.infer_eval import align_first_travel_xy
    except ImportError as exc:
        raise ModelInferenceError("BiWheel3D runtime is missing.") from exc

    candidate_roots = [
        spec.checkpoint.parents[3] if len(spec.checkpoint.parents) > 3 else None,
        Path(__file__).resolve().parents[5] / "BiWheel3D",
        Path(__file__).resolve().parents[4] / "BiWheel3D",
    ]
    imported = False
    for cand in candidate_roots:
        if cand and (cand / "biwheel3d").is_dir():
            if str(cand) not in sys.path:
                sys.path.insert(0, str(cand))
            try:
                from biwheel3d.hybrid_estimator import (
                    HybridEstimatorConfig,
                    run_hybrid_estimator,
                )
                imported = True
                break
            except ImportError:
                continue
    if not imported:
        try:
            from biwheel3d.hybrid_estimator import (
                HybridEstimatorConfig,
                run_hybrid_estimator,
            )
            imported = True
        except ImportError as exc:
            raise ModelInferenceError(
                f"BiWheel3D Unified Hybrid Estimator runtime could not be imported: {exc}"
            ) from exc

    config = HybridEstimatorConfig()
    if spec.checkpoint.is_file():
        try:
            cfg_dict = json.loads(spec.checkpoint.read_text(encoding="utf-8"))
            if isinstance(cfg_dict, dict):
                for k, v in cfg_dict.items():
                    if hasattr(config, k):
                        setattr(config, k, v)
        except Exception:
            pass

    raw_windows = np.asarray(windows, dtype=np.float32)
    if raw_windows.ndim != 3 or raw_windows.shape[1:] != (5, 12):
        raise ModelInferenceError(
            f"Unified Hybrid expected (T,5,12) windows, got {raw_windows.shape}."
        )

    try:
        hyb = run_hybrid_estimator(raw_windows, config=config, dt=config.dt)
    except Exception as exc:
        raise ModelInferenceError(
            f"Unified Hybrid trajectory estimation failed: {exc}"
        ) from exc

    xyz = np.asarray(hyb["xyz"], dtype=np.float64)
    yaw = np.asarray(hyb["psi"], dtype=np.float64)
    v = np.asarray(hyb["v"], dtype=np.float64)
    omega = np.asarray(hyb["omega"], dtype=np.float64)

    aligned_xyz, _ = align_first_travel_xy(xyz, None)
    net_yaw_deg = float(np.degrees(yaw[-1] - yaw[0])) if len(yaw) else 0.0

    return {
        "xy": np.asarray(aligned_xyz[:, :2], dtype=np.float64),
        "signed_speed_mps": v.tolist(),
        "yaw_rad": yaw.tolist(),
        "yaw_rate_radps": omega.tolist(),
        "xy_frame": "first_travel_display",
        "yaw_frame": "initial_chair_heading",
        "net_yaw_deg": net_yaw_deg,
        "yaw_source": "unified_hybrid_inekf_rts",
        "yaw_delay_frames": int(config.yaw_delay_frames),
        "yaw_delay_pad": str(config.yaw_delay_pad),
        "yaw_delay_bursts": 0,
        "gyro_scale": float(config.gyro_scale),
        "chassis_yaw_scale": float(config.chassis_yaw_scale),
        "wheel_radius_m": float(config.wheel_radius_m),
        "track_width_m": float(config.track_width_m),
        "recipe": spec.label,
        "runtime_source": "unified_hybrid_v1",
        "warnings": [
            "Unified Physics-Informed Hybrid Estimator: 3D camber kinematics, dynamic ZUPT/ZARU InEKF, and RTS backward smoothing.",
        ],
    }


def run_session_model(
    repo_root: Path,
    spec: ModelSpec,
    session_data: dict[str, Any],
) -> dict[str, Any]:
    """Run one finalized Results recording through the selected local trajectory model."""
    del repo_root
    ready, detail = model_spec_runtime_status(spec)
    if not ready:
        raise ModelInferenceError(detail)
    try:
        import numpy as np
    except ImportError as exc:  # pragma: no cover - guarded above
        raise ModelInferenceError("NumPy is required for trajectory analysis.") from exc

    import hashlib
    from .analysis_contract import file_identity

    checkpoint_before = file_identity(spec.checkpoint)
    windows, preprocess = prepare_dual_windows(session_data)
    if spec.kind == "onnx":
        model_result = _run_onnx_model(spec, windows, np)
    elif spec.kind == "recipe":
        model_result = _run_recipe_model(spec, windows, session_data, np)
    elif spec.kind == "pytorch_residual":
        model_result = _run_pytorch_residual_model(spec, windows, session_data, np)
    elif spec.kind == "pytorch_residual_slalom_course":
        model_result = _run_pytorch_slalom_course_model(spec, windows, session_data, np)
    elif spec.kind == "unified_hybrid":
        model_result = _run_unified_hybrid_model(spec, windows, session_data, np)
    else:
        raise ModelInferenceError(f"Unsupported model kind: {spec.kind}")

    if file_identity(spec.checkpoint) != checkpoint_before:
        raise ModelInferenceError(
            "Model file changed during analysis; discard result and retry"
        )
    xy = np.asarray(model_result.pop("xy"), dtype=np.float64)
    model_warnings = list(model_result.pop("warnings", []) or [])
    from .analysis_contract import build_analysis

    analysis = build_analysis(
        times=preprocess["time_s"],
        xy=xy.tolist(),
        flags=preprocess["quality_flags"],
        signed_speed=model_result.pop("signed_speed_mps", None),
        yaw=model_result.pop("yaw_rad", None),
        yaw_rate=model_result.pop("yaw_rate_radps", None),
        metadata={
            "model_key": spec.key,
            "model_label": spec.label,
            "model_kind": spec.kind,
            "model_sha256": checkpoint_before,
            "session_id": str(session_data.get("session_id", "")),
            "model_input_sha256": hashlib.sha256(
                np.asarray(windows, dtype="<f4").tobytes()
            ).hexdigest(),
            "model_input_layout": "little-endian float32 (T,5,12), g->m/s2, dps->rad/s",
            "implementation_sha256": {
                p.name: file_identity(p)
                for p in [
                    Path(__file__),
                    Path(__file__).with_name("analysis_timing.py"),
                    Path(__file__).with_name("analysis_contract.py"),
                ]
            },
            "runtime_sha256": {
                p.name: file_identity(p) for p in sorted(_runtime_root().glob("*.py"))
            },
            "source_recording": session_data.get("source_recording"),
            "time_basis": preprocess["time_basis"],
            "overlap_start_s": preprocess["overlap_start_s"],
            "recording_quality": session_data.get("quality", "UNKNOWN"),
            "clock_evidence": preprocess["clock_evidence"],
            "scale_provenance": preprocess["scale_provenance"],
            "xy_frame": model_result.get("xy_frame"),
            "yaw_frame": model_result.get("yaw_frame"),
            "geometry": {
                "wheel_radius_m": model_result["wheel_radius_m"],
                "track_width_m": model_result["track_width_m"],
                "camber_rad": 0.0,
                "source": "inherited_assumptions",
            },
            "calibration": {
                k: model_result.get(k) for k in ("gyro_scale", "chassis_yaw_scale")
            },
            "applied_yaw_delay_frames": model_result["yaw_delay_frames"],
            "warnings": [*preprocess["warnings"], *model_warnings],
            "input_gap_policy": preprocess["input_gap_policy"],
        },
    )
    path_length_m = float(np.linalg.norm(np.diff(xy, axis=0), axis=1).sum())
    endpoint_m = float(np.linalg.norm(xy[-1] - xy[0]))
    return {
        "session_id": str(session_data.get("session_id") or ""),
        "topic": str(session_data.get("topic") or ""),
        "trial_number": session_data.get("trial_number", ""),
        "athlete": str(session_data.get("athlete") or ""),
        "model_key": spec.key,
        "model_kind": spec.kind,
        "model_label": spec.label,
        "checkpoint": str(spec.checkpoint),
        "xy": [(float(x), float(y)) for x, y in xy],
        "point_count": int(xy.shape[0]),
        "path_length_m": path_length_m,
        "endpoint_m": endpoint_m,
        "extent_x_m": float(np.ptp(xy[:, 0])),
        "extent_y_m": float(np.ptp(xy[:, 1])),
        "preprocess": preprocess,
        "analysis": analysis,
        **model_result,
    }


def run_processed_trial_model(
    repo_root: Path, spec: ModelSpec, trial_path: Path
) -> dict[str, Any]:
    """Run a trusted local BiWheel3D processed NPZ directly for research review.

    This is intentionally separate from finalized `.waj` loading. It accepts only
    files inside this checkout's `BiWheel3D/data` tree and never writes the trial.
    C3D overlay metrics are full-cache diagnostics, not the official support-masked
    P1/PyTorch validation score.
    """
    data_root = (Path(repo_root) / "BiWheel3D" / "data").resolve()
    resolved = Path(trial_path).expanduser().resolve()
    try:
        resolved.relative_to(data_root)
    except ValueError as exc:
        raise ModelInferenceError(f"Research trial must be inside {data_root}") from exc
    if not resolved.is_file() or resolved.suffix.lower() != ".npz":
        raise ModelInferenceError(
            f"Choose a processed BiWheel3D .npz trial inside {data_root}"
        )

    ready, detail = model_spec_runtime_status(spec)
    if not ready:
        raise ModelInferenceError(detail)
    try:
        import hashlib
        import numpy as np
        from .analysis_contract import build_analysis, file_identity
        from .biwheel3d_runtime.schema import Trial
    except ImportError as exc:
        raise ModelInferenceError(
            "BiWheel3D research-trial runtime is unavailable."
        ) from exc

    try:
        trial = Trial.load(resolved)
    except Exception as exc:
        raise ModelInferenceError(
            f"Could not load trusted processed trial: {exc}"
        ) from exc
    windows = np.asarray(trial.imu_dual_windows, dtype=np.float32)
    if (
        windows.ndim != 3
        or windows.shape[1:] != (5, 12)
        or len(windows) < MIN_MODEL_STEPS
    ):
        raise ModelInferenceError(
            f"Processed trial has incompatible IMU windows {windows.shape}"
        )
    times = np.asarray(trial.t_gt, dtype=np.float64)
    if (
        times.shape != (len(windows),)
        or not np.isfinite(times).all()
        or np.any(np.diff(times) <= 0)
    ):
        raise ModelInferenceError("Processed trial has invalid model-step timestamps")

    meta = trial.meta
    session_data = {
        "session_id": str(meta.trial_id),
        "topic": str(meta.condition),
        "maneuver": str(meta.maneuver),
        "athlete": str(meta.athlete),
        "trial_number": str(meta.trial_id).rsplit("_", 1)[-1],
        "source_recording": str(resolved),
        "quality": "RESEARCH_PROCESSED_CACHE",
    }
    checkpoint_before = file_identity(spec.checkpoint)
    source_before = file_identity(resolved)
    if spec.kind == "onnx":
        model_result = _run_onnx_model(spec, windows, np)
    elif spec.kind == "recipe":
        model_result = _run_recipe_model(spec, windows, session_data, np)
    elif spec.kind == "pytorch_residual":
        model_result = _run_pytorch_residual_model(spec, windows, session_data, np)
    elif spec.kind == "pytorch_residual_slalom_course":
        model_result = _run_pytorch_slalom_course_model(spec, windows, session_data, np)
    elif spec.kind == "unified_hybrid":
        model_result = _run_unified_hybrid_model(spec, windows, session_data, np)
    else:
        raise ModelInferenceError(f"Unsupported model kind: {spec.kind}")
    if file_identity(spec.checkpoint) != checkpoint_before:
        raise ModelInferenceError("Model file changed during research analysis")
    if file_identity(resolved) != source_before:
        raise ModelInferenceError("Processed trial changed during research analysis")

    xy = np.asarray(model_result.pop("xy"), dtype=np.float64)
    if xy.shape != (len(windows), 2) or not np.isfinite(xy).all():
        raise ModelInferenceError(
            "Research model output does not match processed trial length"
        )
    model_warnings = list(model_result.pop("warnings", []) or [])
    warnings = [
        "Research processed NPZ loaded directly; this is not a finalized .waj recording.",
        "Any C3D metric shown here is a full-cache visual diagnostic; use support-masked evaluation for model claims.",
        *model_warnings,
    ]
    quality_flags = [[] for _ in range(len(times))]
    preprocess = {
        "target_hz": int(meta.imu_hz),
        "model_steps": int(len(windows)),
        "aligned_samples": int(len(windows) * int(meta.sync_ratio)),
        "resampled": False,
        "missing_samples": 0,
        "physical_sync_verified": False,
        "time_s": times.tolist(),
        "quality_flags": quality_flags,
        "time_basis": "processed_trial_t_gt",
        "overlap_start_s": float(times[0]),
        "clock_evidence": {
            "source": "processed_npz",
            "lag_s": float(meta.lag_s),
            "sync_corr": float(meta.sync_corr),
            "note": "Use the trial processing manifest for physical synchronization provenance.",
        },
        "scale_provenance": {"source": "processed_npz_si_windows"},
        "warnings": warnings,
        "input_gap_policy": {"source": "processed_cache"},
    }
    signed_speed = model_result.pop("signed_speed_mps", None)
    yaw_values = model_result.pop("yaw_rad", None)
    yaw_rate = model_result.pop("yaw_rate_radps", None)
    analysis = build_analysis(
        times=times.tolist(),
        xy=xy.tolist(),
        flags=quality_flags,
        signed_speed=signed_speed,
        yaw=yaw_values,
        yaw_rate=yaw_rate,
        metadata={
            "model_key": spec.key,
            "model_label": spec.label,
            "model_kind": spec.kind,
            "model_sha256": checkpoint_before,
            "session_id": str(meta.trial_id),
            "model_input_sha256": hashlib.sha256(
                np.asarray(windows, dtype="<f4").tobytes()
            ).hexdigest(),
            "model_input_layout": "processed SI float32 (T,5,12)",
            "source_recording": str(resolved),
            "source_recording_sha256": source_before,
            "time_basis": preprocess["time_basis"],
            "overlap_start_s": preprocess["overlap_start_s"],
            "recording_quality": "RESEARCH_PROCESSED_CACHE",
            "clock_evidence": preprocess["clock_evidence"],
            "scale_provenance": preprocess["scale_provenance"],
            "xy_frame": model_result.get("xy_frame"),
            "yaw_frame": model_result.get("yaw_frame"),
            "geometry": {
                "wheel_radius_m": model_result["wheel_radius_m"],
                "track_width_m": model_result["track_width_m"],
                "camber_rad": float(meta.alpha),
                "source": "processed_trial_metadata",
            },
            "calibration": {
                k: model_result.get(k) for k in ("gyro_scale", "chassis_yaw_scale")
            },
            "applied_yaw_delay_frames": model_result["yaw_delay_frames"],
            "warnings": warnings,
            "input_gap_policy": preprocess["input_gap_policy"],
        },
    )

    ground_truth_xy = None
    ground_truth_yaw = None
    gt_diagnostic = None
    if bool(meta.has_gt):
        raw_xy = np.asarray(trial.xyz[:, :2], dtype=np.float64)
        left = np.asarray(trial.xyz_left, dtype=np.float64)
        right = np.asarray(trial.xyz_right, dtype=np.float64)
        if (
            raw_xy.shape == xy.shape
            and left.shape[0] == len(xy)
            and right.shape[0] == len(xy)
        ):
            axle_right = right[:, :2] - left[:, :2]
            axle_len = np.linalg.norm(axle_right, axis=1)
            gt_yaw_wrapped = np.arctan2(axle_right[:, 0], -axle_right[:, 1])
            for index in range(1, len(gt_yaw_wrapped)):
                if axle_len[index] < 1e-4:
                    gt_yaw_wrapped[index] = gt_yaw_wrapped[index - 1]
            gt_yaw_abs = np.unwrap(gt_yaw_wrapped.astype(np.float64))
            yaw0 = float(gt_yaw_abs[0])
            c, sn = np.cos(-yaw0), np.sin(-yaw0)
            rel = raw_xy - raw_xy[0]
            gt_xy = np.column_stack(
                [c * rel[:, 0] - sn * rel[:, 1], sn * rel[:, 0] + c * rel[:, 1]]
            )
            gt_yaw = gt_yaw_abs - yaw0
            if np.isfinite(gt_xy).all() and np.isfinite(gt_yaw).all():
                ground_truth_xy = [(float(x), float(y)) for x, y in gt_xy]
                ground_truth_yaw = gt_yaw.astype(float).tolist()
                xy_error = np.linalg.norm(xy - gt_xy, axis=1)
                gt_diagnostic = {
                    "scope": "full_processed_cache_not_support_masked",
                    "ate_rmse_m": float(np.sqrt(np.mean(xy_error**2))),
                    "endpoint_error_m": float(xy_error[-1]),
                }
                if yaw_values is not None:
                    predicted_yaw = np.asarray(yaw_values, dtype=np.float64)
                    if (
                        predicted_yaw.shape == gt_yaw.shape
                        and np.isfinite(predicted_yaw).all()
                    ):
                        gt_diagnostic["heading_unwrapped_rmse_deg"] = float(
                            np.degrees(np.sqrt(np.mean((predicted_yaw - gt_yaw) ** 2)))
                        )

    path_length_m = float(np.linalg.norm(np.diff(xy, axis=0), axis=1).sum())
    endpoint_m = float(np.linalg.norm(xy[-1] - xy[0]))
    return {
        "session_id": str(meta.trial_id),
        "topic": str(meta.condition),
        "trial_number": str(meta.trial_id).rsplit("_", 1)[-1],
        "athlete": str(meta.athlete),
        "model_key": spec.key,
        "model_kind": spec.kind,
        "model_label": spec.label,
        "checkpoint": str(spec.checkpoint),
        "xy": [(float(x), float(y)) for x, y in xy],
        "point_count": int(len(xy)),
        "path_length_m": path_length_m,
        "endpoint_m": endpoint_m,
        "extent_x_m": float(np.ptp(xy[:, 0])),
        "extent_y_m": float(np.ptp(xy[:, 1])),
        "preprocess": preprocess,
        "analysis": analysis,
        "ground_truth_xy": ground_truth_xy,
        "ground_truth_yaw_rad": ground_truth_yaw,
        "gt_diagnostic": gt_diagnostic,
        "research_trial_path": str(resolved),
        **model_result,
    }
