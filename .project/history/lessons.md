# WheelAthlete durable engineering lessons

Updated: 2026-09-08.

These lessons remain applicable to the current Flutter mobile + Python Windows + L/R[/C] firmware architecture.

## Protocol, roles and timing

- Check integer ranges before cross-platform timestamp serialization. Epoch milliseconds do not fit in `uint32`.
- Every high-rate stream needs explicit sequence accounting; loss must be measured, not inferred from a smooth chart.
- Phone/PC receive time is not a substitute for device acquisition time. Preserve clock-map provenance.
- Lifecycle acknowledgement matters: recording success depends on board START/STOP evidence, not only command-write success.
- Adding a new enum role can silently break two-role assumptions. Tests that mean "dual wheel" must explicitly iterate L/R; tests that mean "all supported sensors" may iterate L/R/C.
- Never encode optional-role semantics through a fallback such as "not L means R". That is data corruption when C exists.
- Binary storage needs versioned role semantics. Windows journal v2 exists specifically so side code C cannot be interpreted as R by v1 rules.
- Independently zeroing L/R/C device epochs is not synchronization.

## Acquisition reliability

- Windows UI does not own authoritative raw data; acquisition/parser/journal/QC remain in the daemon.
- Preview traffic is disposable; raw journal traffic is not. Authoritative queue overflow/fault must be visible.
- RSSI is RF context, not integrity. Use sequence gaps, queue drops, transport failures, FIFO faults and journal counts.
- Re-read actual board Info/range after configuration changes so conversion scales cannot remain stale.
- Physical RF, start-skew, gravity-axis and loss claims require physical measurements.
- Keep failed/incomplete captures with reasons. Deleting them hides the denominator.

## Optional center sensor

- C is a chair-frame sensor, not a third wheel. Its semantics differ from L/R hub sensors.
- Current center mounting contract is +Z down; X/Y remain board axes until physically mapped.
- A source/build that supports C is not proof that C improves the model.
- Current L/R model input must be exactly invariant to added C samples. Never extend a legacy tensor by blindly iterating all roles.
- A center-aware model should have an explicit new feature/input version and grouped validation/final data.
- C may be most valuable as chassis-yaw/slip/QC evidence rather than raw-channel concatenation; test that hypothesis instead of assuming 18 channels are better.

## Flutter mobile

- Do not create persistent asynchronous Futures inside `build()`.
- Use Flutter test event-loop tools for storage/async tests to avoid fake-async deadlocks.
- Check `context.mounted` after async gaps.
- Keep BLE/filesystem dependencies behind interfaces/fakes.
- Propagate every configuration field through countdown/recording handoffs; omitted role/range fields can corrupt metadata.
- When adding a role, audit all maps, ternaries, switches, exports and UI counts, not only BLE parsing.
- Conditional `center_raw.csv` is safer than silently changing the old L/R training CSV schema.

## Python Windows

- Keep source and frozen/PyInstaller execution paths explicit.
- Avoid blocking BLE/disk/model work on the Qt UI thread.
- Use ASCII-safe console output where legacy Windows encodings may appear.
- Keep the acquisition daemon alive when closing the GUI would otherwise destroy an active recording.
- A full-suite failure in an unrelated experimental test still prevents claiming the suite green; identify and fix it rather than hiding it with a filtered command.

## Offline analysis/model development

- A saved affine clock map is evidence of the chosen transform, not independent physical sync proof.
- Original bin-center offsets, missingness and frame conventions must survive UI/export.
- XY tangent is not chair yaw during pivots/reverse.
- Analytical contract parity is different from model-accuracy parity.
- A protocol-constrained endpoint near zero is not independent odometry evidence. Always report raw and constrained values.
- Runtime reproducibility is mandatory before accepting an optimizer. Slalom v2 demonstrated that float32 finite-difference quantization can create attractive but non-reproducible metrics.
- Do diagnostic "oracle" experiments to identify the bottleneck, but never ship GT-dependent inference. In Slalom, the GT-yaw oracle showed local yaw-rate waveform/timing mattered more than merely correcting each turn's total angle.
- Reference time-scale drift can masquerade as model phase error. Audit C3D/IMU clock provenance before training a network to absorb it.
- A train-derived calibration that exceeds its learned envelope should fail gracefully/skip, not clip silently to a plausible-looking correction.

## Dataset/reference discipline

- Matching filenames do not prove an IMU/C3D pair.
- `POINT.USED=0` means there are no dynamic point trajectories to relabel.
- Model-derived pseudo markers are visualization aids, never independent labels.
- Keep correlated windows/trials from one participant/session/remount in one split.
- Historical test data that already influenced development cannot become a pristine final holdout later.
- Report all exclusions and denominators.

## Repository/publication hygiene

- Keep installer/build source tracked and generated build/release output ignored.
- Keep one STATUS, one HANDOFF, one active roadmap and one conclusion per phase.
- Archive raw evidence/patch scripts under `.project/local/`; do not multiply current trackers.
- Feature work must not update main/release without explicit authorization.
- Preserve unrelated dirty/staged work, especially separate-repository state.
- A successful compile/test is not a release, install, flash or model promotion.
