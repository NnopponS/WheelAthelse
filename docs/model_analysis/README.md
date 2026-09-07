# Offline motion-analysis API and capture guide

The Windows source app provides experimental classical XY+yaw analysis. The mobile app retains its independent local XY-only M4 ONNX model. Both expose the same time/window and missing-value semantics, not the same estimator.

- [Contract](CONTRACT.md): fields, units, clock provenance, derivative support and export.
- [Capture and acceptance](CAPTURE_AND_ACCEPTANCE.md): physical evidence and independent validation requirements.
- [Synthetic fixtures](fixtures/analysis_v1.json): eleven shared analytical cases, not athlete data.

Current project status, phase conclusions and continuation instructions are centralized under [the engineering workspace](../../.project/README.md). Previous alternate contracts, duplicated final reports and private screenshots remain in the local-only archive; do not treat them as current trackers.
