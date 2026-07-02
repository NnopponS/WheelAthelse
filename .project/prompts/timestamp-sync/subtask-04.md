# PROMPT FOR SUBTASK #31: Verify firmware UTC start computation

ใช้ `cpp-coding-standards` skill + `cpp-testing` skill + `tdd-workflow` skill

## Goal

Verify the firmware's `sendStartFired` correctly computes `utc_start_ms` for the scheduled start path, and fix any unsigned-cast bugs that would cause a late start to produce a wrapped UTC value.

## Context

- `.project/plan-timestamp-sync.md` §Architecture changes
- `.project/context-timestamp-sync.md` §Key design decisions
- Files to touch:
  - `firmware/src/ble_service.cpp` (`sendStartFired`)
  - `firmware/src/ble_types.h` (pack helpers, if needed)
  - `firmware/test/test_ble_types.py` or related host tests

## Current code

```cpp
const int64_t delta_us = static_cast<int64_t>(target_start_us_) -
                         static_cast<int64_t>(now_us);
utc_start_ms = utc_epoch_ms_ + static_cast<uint64_t>(delta_us / 1000);
```

Problem: when `delta_us` is negative (firmware fires a few µs after `target_start_us_`), `static_cast<uint64_t>(delta_us / 1000)` wraps to a huge positive value.

## Required changes

1. Keep the computation in signed 64-bit until the final addition:
   ```cpp
   const int64_t delta_ms = delta_us / 1000;
   utc_start_ms = utc_epoch_ms_ + static_cast<uint64_t>(delta_ms);
   ```
   (C++ integer division truncates toward zero, which is fine here.)
2. Add a host test that exercises negative `delta_us` and asserts the expected `utc_start_ms` is slightly less than `utc_epoch_ms_`.
3. If `utc_epoch_ms_` is 0 (UTC never set), `utc_start_ms` should remain 0.

## Acceptance criteria

- `pio test` or `pytest` firmware tests pass.
- `pio run` succeeds for both wheel build targets.
- A new test demonstrates the negative-delta case produces a sane `utc_start_ms` (no unsigned wrap).

## Before coding

1. Read `.project/plan-timestamp-sync.md` and `.project/context-timestamp-sync.md`.
2. Read `firmware/src/ble_service.cpp` around `sendStartFired` and `handleSetUtc`.
3. Read the existing firmware tests for `packStartFired` / `UtcSet`.
4. Write the failing test first.

## After coding

1. Run `pio test` and `pio run` (left/right).
2. Commit with: `fix(fw): guard UTC start ms against unsigned wrap on late start`
3. Update `.project/progress.md`: mark subtask #31 completed.
