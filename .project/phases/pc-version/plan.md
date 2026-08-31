# WheelAthlete — Windows PC Acquisition Plan

> Branch: `codex/pc-version`
>
> Source task: `pc-version-promt.txt`

| Phase | Deliverable | Status |
|---|---|---|
| 0 | Repository, protocol, firmware, PC-tool, and Flutter audit | done |
| 1 | Feature-parity matrix, target architecture, baseline tests | done (`b970b69`) |
| 2 | XIAO timing, BLE link preferences/diagnostics, FIFO investigation | in progress |
| 3 | Headless Python/Bleak dual-board engine | pending |
| 4 | Clock sync, scheduled start, START/STOP acknowledgements | pending |
| 5 | Append-only journal, recovery, QC, exports | pending |
| 6 | Flutter Windows IPC/backend integration | pending |
| 7 | Preserve and regression-test Android behavior | pending |
| 8 | Windows diagnostics and acquisition UI | pending |
| 9 | Simulated long-run and fault-injection tests | pending |
| 10 | Physical two-XIAO acceptance | blocked: boards unavailable |

## Current loop

1. Finish the ST/Seeed FIFO register design without inventing APIs.
2. Keep TDD RED/GREEN evidence and require both XIAO environments to build.
3. Commit Phase 2 separately.
4. Implement the smallest headless Python collector core with strict parsing,
   bounded queues, monotonic arrival timestamps, and no UI dependency.
5. Continue sequentially; stop on unexplained regression or data-loss risk.

## Definition of done

- Every automated phase has tests and a separate commit.
- Flutter analysis/tests and both firmware environments remain green.
- Simulated fault tests prove fail-closed journal/QC behavior.
- Final hardware claims are withheld until two physical XIAO boards pass the
  prescribed 50/100/200 Hz and long-recording acceptance matrix.
