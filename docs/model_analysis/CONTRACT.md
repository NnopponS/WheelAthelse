# WheelAthlete offline coaching-analysis contract v1

This document describes the implemented software contract, not a claim of physical accuracy. The current Windows model is the frozen legacy BiWheel3D XY+yaw recipe. Mobile retains the original M4 XY-only ONNX asset. P2 research candidates have not been selected or promoted. Shared serialization and statistics do not make the two estimators equivalent.

## Architecture and ownership

Windows: finalized `.waj` journal (or explicitly uncertain legacy CSV) -> `analysis_loader.py` -> `analysis_timing.py` -> existing `model_inference.py` / unchanged bundled runtime -> `analysis_contract.py` -> `AnalysisTimeline` and `ModelPage` -> create-only `analysis_export.py`.

Mobile: saved `BufferedSample` + `SessionMeta` -> `analysis_timing.dart` and existing `prepareTrajectoryInput` in a compute isolate -> unchanged M4 feature/inference graph -> `analysis_contract.dart` -> `AnalysisReview` / `TrajectoryChart` -> `analysis_export.dart`.

The acquisition daemon, firmware, raw-recording schema, model weights, calibration, and `current_best` recipe are not changed by these phases. There is no HTTP model server and no new service or dependency. Computational work and model state belong to one full recording. Cursor/window controls select from that result; they never rerun inference or restart its pose.

## Time: origin, clock evidence and uncertainty

`time_s` is the center of a five-sample input bin, in seconds relative to recording start. Input is resampled to 100 Hz; model output is 20 Hz. A bin with source times 4.20, 4.21, 4.22, 4.23 and 4.24 s has time 4.22 s, not 0.02 s. The overlap offset is retained, every complete five-sample group is kept, and any incomplete tail count is reported.

For Windows journals with complete evidence, the loader reads the immutable SESSION_META, the most recent SYNC model for each side before START, and the common scheduled `pc_start_ns`. The saved mapping is `pc_ns = slope_ns_per_us * device_us_unwrapped + intercept_ns`. It reconstructs the uint32 epoch from the scheduled target and the inverse of that same model. It does not independently zero the two board clocks or fit an offset from the motion. A contradictory target/model or reset is rejected. Later post-stop models are not retrospectively substituted into the pre-START epoch.

The map records BLE midpoint-based observations, not external synchronization truth. Its residuals/counts/rates are preserved as evidence. Software checks cannot establish physical capture simultaneity, sensor group delay, correct oscillator rate, or motion-reference alignment. `physical_sync_verified` remains false.

Older Windows results without the complete saved map keep their legacy nominal sequence cadence, anchored to the supplied receipt-relative origin. This fallback is labeled `legacy_sequence_arrival_anchor`, with a warning. Supplied recording-relative times can also be explicitly declared for an importer. A broken saved map does not silently downgrade to the fallback.

Mobile retains the saved START-relative timestamps. Only a completely repeated legacy timeline may use a labeled sequence-cadence fallback; a partly nonmonotonic timeline is rejected. Legacy absolute UTC samples require the recorded UTC start. Session metadata is insufficient to reconstruct or certify all historical affine maps and physical sensor ranges. These limitations are carried into the result, rather than replacing them with confidence percentages.

## Raw input and data-quality policy

Both sides are required. Nonfinite axes/times, partially missing counters, contradictory repeats, nonmonotonic device clocks, incompatible epochs and mismatched Windows configured side rates fail analysis. Sequence counters are unwrapped, identical replay duplicates are counted, and late recovered samples are placed into their sequence epoch. A counter can be unwrapped without pretending that a clock reset is a wrap.

A raw interpolation bracket greater than 0.050 s is rejected. Device timestamps are checked too, so nominal cadence cannot conceal a device-time outage. At or below this limit, missing samples can be interpolated and the affected output bins receive `small_gap_interpolated`. This is an explicit conservative analysis policy, not a modification of acquisition QC or the P1/P2 optical-reference gates. No excluded research trial is recovered by this policy.

Windows raw int16 endpoints are flagged as `sensor_clipping`. Mobile's current persisted values do not retain a trustworthy per-sample raw-range certificate, so absence of a clipping flag must not be interpreted as proof that saturation never occurred. Inherited geometry remains radius 0.30 m, track/hub spacing 0.52 m, camber zero; these are assumptions, not measurements from this task. The model's calibration constants remain unchanged.

Immutable capture scales take precedence over a renamed/edited summary. Loading an old Windows recording never borrows the currently connected board's range. A missing scale uses an explicitly labeled legacy assumption, and malformed recorded scales fail instead of being silently replaced.

## Envelope and fields

The JSON envelope contains `schema_version: 1`, `metadata`, and `samples`. Metadata records algorithm/contract identity, offline mode, model SHA-256, geometry, calibration where available, time basis, clock evidence, warnings, derivative support, input-QC policy and coverage. Windows additionally records its prepared-input SHA-256 and the current inference/contract/runtime source hashes. Historical `biwheel3d_runtime/SOURCE.json` is not treated as a hash of the present working tree.

All mandatory numbers must be finite. Unavailable optional numbers are JSON `null`, never NaN, Infinity, an empty string in JSON, or a fabricated zero. JSON readers reject missing required fields, nonincreasing time, negative speed magnitude, and contradictory signed/magnitude speed. Mobile also rejects an analysis envelope whose length or XY coordinates disagree with the displayed trajectory.

| Field | Units and meaning | Windows frozen recipe | Mobile current M4 |
|---|---|---|---|
| `time_s` | seconds, original recording-relative bin center | available | available with saved-time provenance |
| `x_m`, `y_m` | metres, relative planar estimate in declared XY frame | available | available |
| `signed_speed_mps` | m/s, positive forward and negative reverse | estimator output | null |
| `speed_mps` | m/s, nonnegative magnitude | absolute signed estimator speed | magnitude of local-linear XY derivatives; explicitly derived |
| `longitudinal_accel_mps2` | m/s2, derivative of signed forward speed | available only with complete derivative support | null |
| `yaw_rad` | radians, unwrapped chair orientation | estimator output | null |
| `yaw_rate_radps` | rad/s, chair angular rate | estimator output | null |
| `lateral_accel_mps2` | m/s2, optional no-slip-derived quantity | null pending validated support | null |
| `speed_change_mps2` | m/s2, derivative of speed magnitude, not signed longitudinal acceleration | derived | derived when both derivative stages have support |
| `quality_flags` | array of named facts, not confidence probabilities | input and derivative flags | input, derivative and XY-only capability flags |

The legacy Windows display can rotate XY toward the first direction of travel while yaw remains in the initial-chair-heading frame. Both frames are named separately. The software does not silently rotate one into the other, infer chair yaw from the path tangent, or infer zero yaw from a stationary XY trace. This matters for reversing and in-place spins.

## Derivatives, edges and latency

The implemented derivative is a centered seven-sample local-linear least-squares slope on actual timestamps. On uniform 20 Hz samples, its first derivative equals the symmetric SG(7,2) derivative; for irregular timestamps it is specifically a local-linear fit, not a general quadratic Savitzky-Golay filter. Its nominal first-to-last support spans 0.30 s.

The first and last three samples are unavailable. Any missing value, flagged gap/clipping sample in the stencil, or model-step interval greater than 0.075 s invalidates that derivative. There is no zero padding, copied edge peak, or slope estimate across a long outage. A second derivative stage, such as change in XY-derived speed magnitude, has additional missing edge/support samples.

The underlying recipe and M4 graph include whole-session/centered operations. These are offline outputs. No live-latency bound or causal streaming capability is claimed. A selected window does not change the derivative support or the previously computed values.

## Cursor, windows and descriptive statistics

The cursor addresses a full-resolution sample index. Nearest-time lookup uses the earlier sample for an exact tie and clamps outside the available range. Native Qt controls also provide keyboard stepping. Flutter controls retain source indices rather than indexing a decimated plot.

A selected window includes both boundary sample centers. Window statistics report exact indices, count, center-to-center duration, estimated path length, net unwrapped yaw when available, and per-channel min/max/count and time-weighted mean. Means use trapezoidal integration over adjacent nonnull samples and report the actual supported duration. With no supported interval, mean is null. These are descriptive estimates, not independent truth or a certification that a flagged input was physically correct; flags and warnings must accompany interpretation.

A one-sample selection has zero elapsed duration and no supported mean/net-turn interval. Null derivatives are not counted as zero acceleration. Selecting a later window does not translate its XY or yaw origin back to zero. Display decimation is allowed only for rendering: all samples still determine bounds, cursor lookup, statistics and export.

## Export and compatibility

Each export creates a unique child folder beneath the directory selected by the user. It writes the complete `timeline.csv`, `metadata.json`, and a `COMPLETE` marker last. It never writes the original `.waj`, raw CSV, model or earlier export. An incomplete IO operation leaves a clearly incomplete new folder; there is no broad cleanup of the user's directory.

CSV uses the field names above (units embedded), empty numeric cells for unavailable values, and a properly quoted JSON array for flags. The sidecar contains the row count, column contract, the SHA-256 of the CSV, model/time/QC metadata, and the requested selected-window statistics. The CSV is full-session, not a silently cropped/re-zeroed window export. A consumer should require COMPLETE and verify the sidecar hash before accepting an export as complete.

The original Windows result keys (`xy`, path/endpoint summaries and other display metadata) remain. `analysis` is additive. Mobile `TrajectoryResult.analysis` is optional so older XY-only results and existing providers continue to load. A legacy result without a full analysis envelope must not receive invented timestamps or orientation merely to populate the new controls.

## Verification boundaries

Shared fixtures in `fixtures/analysis_v1.json` cover forward/reverse motion, both arcs, repeated pivots, start/stop, irregular clocks, short support, flagged gaps and XY-only cases. Python and Dart compare complete output envelopes and window statistics. These fixtures verify numerical/serialization conventions, not athlete accuracy or the equivalence of the two production estimators.

See the execution ledger and team review for exact test counts, failures fixed during implementation, real-journal smoke results and source screenshots. A source/widget screenshot is not an Android installation test; a successful journal read or saved affine map is not a synchronized optical-reference experiment.


## Feature-branch validation refinements

JSON version one does not accept Python boolean `true` as an integer version. Metadata keys must remain strings and nested values must be JSON primitives, arrays or objects on both platforms. Mobile rejects mixed UTC/recording-relative arrays and a large sequence hole even when saved timestamps appear smooth. A repeated UTC clock fallback is explicitly named as nominal sequence timing.

Mobile export encoding, content hashing and statistics execute in a compute isolate; original source arrays, CSV field definitions and selected-window semantics are unchanged. This performance separation is tested with a synthetic 8,000-point recording, not asserted as a physical-device benchmark.
