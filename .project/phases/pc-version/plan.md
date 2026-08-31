# WheelAthlete — Windows PC Acquisition Plan

> Branch: `codex/pc-version`
>
> Source task: `pc-version-promt.txt`

| Phase | Deliverable | Status |
|---|---|---|
| 0 | Repository, protocol, firmware, PC-tool, and Flutter audit | done |
| 1 | Feature-parity matrix, target architecture, baseline tests | done (`b970b69`) |
| 2 | XIAO timing, BLE link preferences/diagnostics, FIFO investigation | done (`8d0d0a9`) |
| 3 | Headless Python/Bleak dual-board engine | done (`857a164`) |
| 4 | Clock sync, scheduled start, START/STOP acknowledgements | done (`da6249a`) |
| 5 | Append-only journal, recovery, QC, exports | done (`118e1bc`) |
| 6 | Flutter Windows IPC/backend integration | done (`a8927ae`) |
| 7 | Preserve and regression-test Android behavior | done (`4b4aef9`) |
| 8 | Windows diagnostics and acquisition UI | done |
| 9 | Simulated long-run and fault-injection tests | in progress |
| 10 | Physical two-XIAO acceptance | blocked: boards unavailable |

## Current loop

1. Run accelerated 30-minute-equivalent dual-wheel simulations at 50/100/200 Hz.
2. Exercise notification bursts, writer backpressure, preview/UI isolation,
   sequence integrity and fail-closed QC behavior.
3. Re-run release gates and document exact automated evidence.
4. Keep physical RF/synchronization claims gated on two real XIAO boards.

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
- Windows release build requires a machine with the Flutter-supported Visual
  Studio Desktop development with C++ toolchain; this host currently lacks it.
- Final hardware claims are withheld until two physical XIAO boards pass the
  prescribed 50/100/200 Hz and long-recording acceptance matrix.
