# WheelAthlete — Windows PC Acquisition Plan

> Branch: `codex/pc-version`
>
> Source task: `pc-version-promt.txt`

| Phase | Deliverable | Status |
|---|---|---|
| 0 | Repository, protocol, firmware, PC-tool, and Flutter audit | done |
| 1 | Feature-parity matrix, target architecture, baseline tests | done (`b970b69`) |
| 2 | XIAO timing, BLE link preferences/diagnostics, FIFO investigation | done (`8d0d0a9`) |
| 3 | Headless Python/Bleak dual-board engine | done |
| 4 | Clock sync, scheduled start, START/STOP acknowledgements | in progress |
| 5 | Append-only journal, recovery, QC, exports | pending |
| 6 | Flutter Windows IPC/backend integration | pending |
| 7 | Preserve and regression-test Android behavior | pending |
| 8 | Windows diagnostics and acquisition UI | pending |
| 9 | Simulated long-run and fault-injection tests | pending |
| 10 | Physical two-XIAO acceptance | blocked: boards unavailable |

## Current loop

1. Add strict Sync-event parsing and a monotonic PC/device clock model.
2. Collect repeated pre-record round trips, map one future PC T0 to both device
   clocks, and require START_FIRED acknowledgements.
3. Implement bounded STOP retry/ack without introducing periodic dual-wheel
   control traffic during acquisition.
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
