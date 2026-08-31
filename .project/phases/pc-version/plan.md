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
| 5 | Append-only journal, recovery, QC, exports | done |
| 6 | Flutter Windows IPC/backend integration | in progress |
| 7 | Preserve and regression-test Android behavior | pending |
| 8 | Windows diagnostics and acquisition UI | pending |
| 9 | Simulated long-run and fault-injection tests | pending |
| 10 | Physical two-XIAO acceptance | blocked: boards unavailable |

## Current loop

1. Define and test a versioned localhost TCP NDJSON protocol with strict size,
   type, request-id, and protocol-version validation.
2. Run the Python acquisition daemon independently from Flutter rendering.
3. Add a Dart desktop client/backend selected only on Windows while Android
   continues to use the existing FlutterBluePlus path.
4. Raw IMU samples stay inside the daemon; Flutter receives only throttled
   preview and telemetry/status events.

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
