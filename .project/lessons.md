# WheelAthlete — Durable Engineering Lessons

Only lessons that remain relevant to the current mobile + Python Windows architecture are kept here.

## Protocol and timing

- Check integer ranges before serializing timestamps across platforms. Epoch milliseconds do not fit in `uint32`.
- Every high-rate stream needs explicit sequence accounting; packet loss must be detectable rather than inferred from UI behavior.
- Raw phone/PC receive timestamps are not sufficient for dual-wheel alignment. Maintain clock-offset/drift estimation and clear timestamp provenance.
- Lifecycle acknowledgement matters: recording success should depend on actual board START/STOP events, not only a successful command write.

## Acquisition reliability

- UI rendering must never own the authoritative raw-data path on Windows. Keep BLE/parser/journal/QC in the acquisition daemon.
- Preview traffic is disposable; raw journal traffic is not. Bounded preview queues may drop frames, authoritative queues must fail visibly rather than overwrite unread data.
- RSSI is RF context, not an integrity metric. Sequence gaps, queue drops, transport failures, FIFO faults, and journal counts are the integrity signals.
- Re-read firmware Info after range changes so raw-to-physical scale factors cannot stay stale.
- Physical RF/start-skew claims require physical measurements; simulation is not evidence for radio behavior.

## Flutter mobile

- Do not create a new Future inside `build()` for persistent asynchronous data; cache or model it as state to avoid rebuild/pump loops.
- In widget tests, use the Flutter test event-loop tools for asynchronous storage flows when fake async behavior would otherwise deadlock.
- Use `context.mounted` after async gaps before accessing UI context.
- Keep external BLE/filesystem dependencies behind interfaces with fakes so domain/state logic remains testable.
- When extending configuration models, propagate every field through countdown/record handoffs; missing fields can silently corrupt metadata.
- Riverpod 3.x uses Notifier/NotifierProvider patterns; do not reintroduce removed legacy provider APIs.

## Python Windows

- Keep Windows source execution and frozen/PyInstaller execution paths explicit. The GUI must find either the source daemon module or bundled daemon executable.
- Avoid blocking BLE or disk work in the Qt UI thread. IPC should remain event-driven.
- Use ASCII-safe console output where scripts may run under legacy Windows console encodings.
- Leave the acquisition daemon alive if an active recording would otherwise be destroyed by closing the GUI.

## Packaging and repository hygiene

- Keep installer/build source under `packaging/windows/`; keep generated `build/` and `release/` output untracked.
- Keep `.project` small and canonical. Old plans/prompts belong in Git history, not in active project state.
- Keep mobile, firmware, BLE contract, README, and Windows package versions synchronized with automated checks.
- Work on `codex/pc-version` must not mutate `main` unless explicitly requested.
