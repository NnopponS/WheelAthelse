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
| 6 | Flutter Windows IPC/backend integration | done |
| 7 | Preserve and regression-test Android behavior | in progress |
| 8 | Windows diagnostics and acquisition UI | pending |
| 9 | Simulated long-run and fault-injection tests | pending |
| 10 | Physical two-XIAO acceptance | blocked: boards unavailable |

## Current loop

1. Run the complete Flutter suite/analyzer against the existing Android/mobile
   state machines, not only desktop tests.
2. Ensure production mobile BLE construction remains FlutterBluePlus and no
   desktop daemon dependency is introduced into Android acquisition paths.
3. Add a platform-boundary regression test before building desktop UI.
4. Treat the missing Visual Studio C++ toolchain as an environment blocker for
   `flutter build windows`, not as passing build evidence.

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
