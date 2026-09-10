# Portable model bundles

WheelAthlete 1.8.2 can load a model from a self-contained directory in the user model library (`Documents/WheelAthlete/Model`). Put the artifact and a manifest named `wheelathlete-model.json` in one direct child directory, then choose **Refresh models**. The bundle must not depend on the source checkout or the separate `BiWheel3D` repository.

```text
Documents/WheelAthlete/Model/
  my-model/
    wheelathlete-model.json
    model.onnx
```

The version 1 manifest is:

```json
{
  "schema_version": 1,
  "model_id": "org.example.wheel-model.v1",
  "display_name": "Example v1",
  "model_version": "1.0.0",
  "runtime": {
    "kind": "onnx",
    "requires": ["numpy", "onnxruntime"]
  },
  "artifact": "model.onnx",
  "preprocessing": {
    "id": "biwheel3d_features_v1",
    "sample_rate_hz": 100,
    "feature_dim": 90
  },
  "required_sensor_roles": ["L", "R"],
  "outputs": [
    {"name": "x_m", "unit": "m"},
    {"name": "y_m", "unit": "m"}
  ],
  "experimental": true,
  "description": "Technical purpose and validation status."
}
```

## Supported runtime contracts

| `runtime.kind` | preprocessing ID | feature dimension | exact `runtime.requires` | artifact |
|---|---:|---:|---|---|
| `recipe` | `biwheel3d_dual_hub_v1` | 60 | `numpy` | supported recipe JSON |
| `onnx` | `biwheel3d_features_v1` | 90 | `numpy`, `onnxruntime` | `.onnx` |
| `pytorch_residual` | `biwheel3d_residual_features_v1` | 88 | `numpy`, `torch` | `.pt` or `.pth` |
| `pytorch_residual_slalom_course` | `biwheel3d_residual_features_v1` | 88 | `numpy`, `torch` | `.pt` or `.pth`, plus relative `course_config` |
| `unified_hybrid` | `biwheel3d_dual_hub_v1` | 60 | `numpy`, `scipy`, `biwheel3d` | configuration JSON |

All current adapters require roles `L` and `R` at 100 Hz. Every output is an object containing a supported contract field and its exact unit from [CONTRACT.md](CONTRACT.md); `x_m` and `y_m` are required. Experimental status affects labeling, not validation.

WheelAthlete resolves `artifact` and `course_config` inside the bundle directory before loading. It rejects absolute paths, parent traversal, missing files, incompatible extensions, unknown runtimes, wrong preprocessing identities or dimensions, unsupported schema versions, invalid output units, and missing runtime packages. Raw Python model architectures are not loaded dynamically; export them through one of the supported adapters.

Existing standalone recipe, ONNX, and PyTorch imports remain supported for legacy libraries. Portable bundles are the standard format for new models because they carry the model, input contract, capabilities, and runtime requirements together.
