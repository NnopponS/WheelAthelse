# WheelAthlete — Windows PC Acquisition Plan

> Branch: `codex/pc-version`
>
> Source task: `pc-version-promt.txt`

| Phase | Deliverable | Status |
|---|---|---|
| 0 | Repository, protocol, firmware, PC-tool, and Flutter audit | done |
| 1 | Feature-parity matrix, target architecture, baseline tests | done (`b970b69`) |
| 2 | XIAO timing, BLE link preferences/diagnostics, FIFO investigation | done |
| 3 | Headless Python/Bleak dual-board engine | in progress |
| 4 | Clock sync, scheduled start, START/STOP acknowledgements | pending |
| 5 | Append-only journal, recovery, QC, exports | pending |
| 6 | Flutter Windows IPC/backend integration | pending |
| 7 | Preserve and regression-test Android behavior | pending |
| 8 | Windows diagnostics and acquisition UI | pending |
| 9 | Simulated long-run and fault-injection tests | pending |
| 10 | Physical two-XIAO acceptance | blocked: boards unavailable |

## Current loop

1. Build the smallest headless Python collector core with strict parsing,
   bounded per-board queues, monotonic arrival timestamps, and no UI dependency.
2. Keep the BLE transport behind an interface so tests do not require hardware.
3. Add clock synchronization and deterministic lifecycle only after ingestion
   is fail-closed and tested.
4. Continue sequentially; stop on unexplained regression or data-loss risk.

## Phase 2 hardware gate

FIFO activation is deliberately deferred until physical XIAO hardware is
available. The ST/Seeed register contract and XIAO INT1 wiring support a future
FIFO/DRDY implementation, but sample pattern alignment, watermark behavior,
timestamp reconstruction, and overrun accounting have not been observed on the
actual board. The release path therefore keeps the lower-risk coherent 12-byte
register burst with BDU + auto-increment and midpoint timestamping.

## Definition of done

- Every automated phase has tests and a separate commit.
- Flutter analysis/tests and both firmware environments remain green.
- Simulated fault tests prove fail-closed journal/QC behavior.
- Final hardware claims are withheld until two physical XIAO boards pass the
  prescribed 50/100/200 Hz and long-recording acceptance matrix.
