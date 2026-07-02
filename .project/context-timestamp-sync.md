# Timestamp Sync — Context / Decisions

## User questions and answers

### Q1: What does "00 millisecond" mean?

**Answer:** Start recording exactly on a whole-second boundary (e.g., `18:30:26.000`). The CSV timestamps do **not** need to be resampled onto a fixed grid.

### Q2: What should `timestamp_synced_ms` contain?

**Answer:** Absolute UTC epoch milliseconds (e.g., `1782993025000.000`). It should be directly comparable to the camera's clock.

### Q3: How should the countdown behave?

**Answer:** Wait for the next whole-second boundary, then run the existing 5-second countdown. This means the total delay from pressing Start to the first sample is `5 s + (0..1000) ms`.

## Constraints

- Keep the existing 5-4-3-2-1 in-app countdown and 3-2-1 beep semantics.
- Do not change the BLE protocol format.
- Do not break existing immediate-start path in `RecordingNotifier.startRecording` (it may still be used by tests or future callers).
- Use the existing drift-fit + scheduled-start infrastructure; do not add a new NTP/RTC dependency.

## Key design decisions

1. **UTC offset per session**: The countdown provider computes `utcOffsetMs = utcStartMs - tStartRelMs` and passes it through `SessionConfig`. The recording provider adds this offset to every sample.
2. **Fallback**: If `utcStartMs` is `null` (legacy/immediate start), the recording provider keeps the current relative `timestampSyncedMs`.
3. **Meta start time**: `SessionMeta.startTime` should be the UTC start instant (`DateTime.fromMillisecondsSinceEpoch(utcStartMs, isUtc: true)`) rather than the phone-local time when START_FIRED arrived.
4. **Firmware unsigned-cast bug**: The existing `sendStartFired` casts `delta_us / 1000` to `uint64_t` without guarding against a negative value. This can wrap if the start fires slightly after `target_start_us`. Subtask #4 fixes it to `int64_t` / `static_cast<int64_t>` before adding to `utc_epoch_ms_`.
