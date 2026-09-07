# P7 capture and end-to-end acceptance record

Date: 2026-09-08. Status: **capture protocol and software-readiness evidence prepared; physical capture and athlete/coach acceptance pending**.

No hardware was added, no device was flashed, no application was installed, and no new athlete measurement was collected by this continuation. The checklist below is a protocol to execute with the team; an unchecked field is not a completed test.

## 1. Separate the kinds of acceptance

| Evidence category | What can establish it | Current boundary |
|---|---|---|
| Mathematical contract | Analytical fixtures, Python/Dart parity, null/units/time checks | Software tests recorded in phase review |
| Source application behavior | Source UI tests, exact cursor/window/export comparison, screenshots | Windows source and Flutter widget evidence; not installed-device acceptance |
| Native model execution | Actual existing ONNX graph running through the installed host runtime | Host native checks; not Android/iOS hardware validation |
| Recording integrity | CRC/finalization, raw hashes, both stream counts and gap/replay accounting | Existing journals inspected read-only; not new field capture |
| Device identity and configuration | Read device information, flashed build identity, register/range evidence | Must be confirmed during physical capture |
| Physical synchronization | Independent common timing evidence mapped to both IMUs and optical system | Not certified by saved affine models alone |
| Motion accuracy | Independent valid optical reference, predeclared metrics and held-out groups | Blocked by reference data |
| Coach usefulness | Athlete/coach executes the full review workflow and signs off | Pending named reviewer and observed session |

## 2. Before collecting any new recording

Assign a capture operator, data steward and reviewing coach. Record the chair ID, athlete ID under the team's consent/privacy process, load configuration, surface, date/time, session ID and protocol version. Retain the raw files privately; do not upload identifiable recordings or raw data to source control.

Measure or explicitly record as unknown: left/right loaded wheel radius, hub spacing, camber, marker offsets and each IMU's location/orientation. Current software assumptions remain 0.30 m radius, 0.52 m hub spacing and zero camber until a separately reviewed change is justified. Do not silently replace these with visually estimated dimensions.

For each device, record hardware/chip identity, firmware version and build/hash when available, selected accelerometer/gyro ranges, advertised raw-to-unit factors, configured sample rate and observed acquisition cadence. Keep raw integer samples and original timestamps whenever the capture system supports them. A scale inferred from CSV quantization is diagnostic, not a substitute for this configuration record.

Confirm that the optical system exports actual moving left/right wheelchair-hub markers. Retain marker names, units, rate, residuals/validity, marker-to-hub interpretation and the original export. Check POINT.USED and inspect moving trajectories before the athlete leaves. A blank C3D, foot/gait markers or a rendered overlay does not satisfy this requirement.

Freeze the intended trial list, exclusion policy, metric definitions, derivative support and grouped split assignment in advance. Preserve a separate day/athlete/remount group for final testing. Do not move difficult trials between partitions after looking at their errors.

## 3. Synchronization evidence

Save the common planned start, acknowledged start events from both devices, original device counters, sequence numbers, arrival timestamps and every available clock observation/model. Retain both pre-start and post-stop evidence with phase labels. Do not delete clock discontinuities or overwrite old synchronization fields after a trial.

Document an independently observable event or synchronization method common to the optical reference and both IMUs. Record its uncertainty and how it is mapped onto the saved recording timeline. Do not assume that independent starts become synchronized merely by setting each one to zero. Do not estimate a separate trajectory-fitting time warp for each scored window.

Capture stationary periods at the start and end where safely possible. Label externally observed stillness, not merely low gyro values. Check all gyro axes and acceleration stability; a quiet wheel-spin component alone is insufficient. Insufficient rest must remain an explicit outcome rather than triggering a forced bias correction.

After a reset, reconnection, dropped start acknowledgement or ambiguous counter rollover, create a new recording epoch. Keep the failed attempt and reason in the intended-trial manifest. Do not merge two epochs into a continuous trusted path.

## 4. Maneuver set and replication

The operator and coach should agree what each maneuver name means, including distance, direction, number of repetitions/turns and start/stop rules. Avoid imposing a presumed total yaw such as 1800 degrees as calibration truth.

| Maneuver family | Required observations |
|---|---|
| Static start/end | Externally observed rest, residual gyro and acceleration, timing anchors |
| Straight motion | Smooth acceleration, constant-speed travel, braking and restart |
| Reverse | Negative signed forward speed distinguished from speed magnitude |
| One-wheel arcs | Left-driven and right-driven; forward and reverse where safe |
| In-place rotation | Both directions, including complete turns; preserve unwrapped yaw |
| Slalom / tight turns | Alternating turn direction, transient acceleration and possible slip |
| Shuttle protocol | Actual measured route/turn count and complete retained motion |
| Pause/restart | Several stops, resumed motion and any delayed heading leakage |

Collect multiple trials and, as feasible, multiple days, athletes and remounts. Group allocation must keep all windows from a recording together. The team should decide safe maneuver intensity; software development does not replace clinical or sports-supervision judgment.

## 5. Immediate data checks before leaving the capture site

- [ ] Both wheel streams are present with original acquisition timestamps and configured ranges.
- [ ] Journal/export integrity and finalization pass; originals are hashed and retained.
- [ ] Sequence holes, duplicates, replays, resets and losses are counted rather than hidden.
- [ ] The common-start and optical-to-both-IMU mapping is documented with uncertainty.
- [ ] Moving wheel markers, residuals, units and rates are valid in the actual exported C3D.
- [ ] Full motion for each intended trial is retained, including start/end and difficult turns.
- [ ] Trial identities, labels, group allocation and all failed attempts are complete.
- [ ] No QA threshold or calibration parameter was altered to make this capture pass.

## 6. Athlete/coach workflow acceptance

Use an independently identifiable finalized recording, not a synthetic demonstration. Note the source/software version, model SHA, output time basis, quality warnings, and whether the test is source-level or an installed release on a named device.

First load the recording and generate an offline estimate while checking that acquisition ownership is not duplicated. On Windows, select several individual timestamps with keyboard and pointer. On mobile, move the time slider and range handles. The selected trajectory point must correspond exactly to the underlying full-resolution sample, even when the displayed line is decimated.

Select a window that starts well after recording start. Verify that its XY/yaw origin does not reset, the endpoints are inclusive sample centers, elapsed time agrees with the timestamps, and the displayed min/max/mean/counts match exported values. Verify derivative edges and gaps are unavailable rather than zero. At a pivot, Windows must retain chair yaw without translational motion. On the current XY-only mobile model, chair yaw, yaw rate, signed speed and signed longitudinal acceleration must remain unavailable, not replaced by path tangent.

Switch recordings/models while an analysis is in progress; the old result must not be assigned to the new selection. Cancel an export and verify nothing was written. Perform a successful export into a new folder, verify COMPLETE, CSV SHA, row count, column units, null encoding and selected-window metadata. Confirm original recording bytes remain unchanged.

The coach should explain which displayed quantities are usable for the intended training decision and which uncertainty warnings prevent interpretation. Record requested tolerances and unacceptable maneuver-specific failures before a locked accuracy evaluation. A positive UI review does not approve the model's physical accuracy.

## 7. Acceptance form

Capture session / data owner: ____________________

Athlete consent/handling record: ____________________

Chair / devices / firmware / range record: ____________________

Optical export identity and marker mapping: ____________________

Independent synchronization method and uncertainty: ____________________

Training / validation / locked-final group allocation: ____________________

Software source or installed build / model SHA: ____________________

Windows hardware / display resolution: ____________________

Mobile platform / device / OS / installed build: ____________________

Observed UI/export issues: ____________________

Motion-accuracy report and coverage: ____________________

Coach decision, limitations and signature/date: ____________________

Data-steward approval for one final-test evaluation: ____________________

Status must be one of: pending, blocked, rejected, provisional with explicit scope, or accepted with signed evidence. Never infer a physical acceptance checkbox from a passing unit test or a successful build.
