# Offline motion-analysis API and capture guide

The Windows source app provides experimental classical XY+yaw analysis. The mobile app retains its independent local XY-only M4 ONNX model. Both expose the same time/window and missing-value semantics, not the same estimator.

The Windows **Model** page now offers a planar chart and a mouse-orbit 3D trajectory view. A model that returns measured/estimated XYZ supplies its actual Z coordinates; XY-only models are shown on a clearly labeled Z=0 plane for viewing and do not acquire a height estimate. The optional frozen SIF yaw-consensus research artifact can be selected from a local `BiWheel3D` checkout for finalized L/R/C recordings; it is not the application default or a portable installed-app model. CSV includes `z_m` only when the model returned Z, leaving the field empty for planar models. The image button exports whichever view is selected.

- [Contract](CONTRACT.md): fields, units, clock provenance, derivative support and export.
- [Capture and acceptance](CAPTURE_AND_ACCEPTANCE.md): physical evidence and independent validation requirements.
- [Synthetic fixtures](fixtures/analysis_v1.json): eleven shared analytical cases, not athlete data.

Current project status, phase conclusions and continuation instructions are centralized under [the engineering workspace](../../.project/README.md). Previous alternate contracts, duplicated final reports and private screenshots remain in the local-only archive; do not treat them as current trackers.
