# WheelAthlete — Windows PC Acquisition Plan

> Branch: `codex/pc-version`
>
> Source task: `pc-version-promt.txt`
>
> Hard branch rule: **never merge/push this work into `main` unless the user
> explicitly reverses that instruction in a future message.**

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
| 8 | Windows diagnostics and acquisition UI | done (`083d7c8`) |
| 9 | Simulated long-run and fault-injection tests | done; phase commit pending |
| 10 | Physical two-XIAO acceptance | execution blocked: boards unavailable; harness preparation next |

## Current loop

Automated implementation phases 0–9 are complete and green. Before declaring
all work that can be completed without hardware finished:

1. prepare a Phase 10 physical-acceptance CLI/harness that reuses the real
   `AcquisitionService` and `.waj` evidence rather than a second acquisition
   implementation;
2. encode the 50/100/200 Hz, distance, long-run, and repeated Start/Stop matrix
   in testable plan-generation logic;
3. generate a machine-readable physical acceptance report from finalized
   journal evidence;
4. test the harness logic without making physical-success claims;
5. leave only the actual two-XIAO runs blocked until hardware is attached.

## Phase 9 automated acceptance

The following automated gates are complete:

- dual-wheel 30-minute-equivalent simulations at 50/100/200 Hz;
- 400-notification burst per wheel;
- dual 200 Hz journal test: 720,000 authoritative raw samples;
- slow-disk queue backpressure fail-closed behavior;
- simulated disk-write exception → fatal writer fault;
- journal/host sample-count integrity check;
- slow/frozen Flutter UI preview isolation with 256 KiB bounded preview socket
  threshold;
- diagnostic report includes IPC preview sent/dropped/buffer counters;
- PC acquisition tests: 31 passed;
- desktop Flutter tests: 8 passed;
- full Flutter tests: 645 passed;
- Dart analyzer: no issues;
- XIAO tests: 15 passed;
- XIAO LEFT/RIGHT firmware builds: success;
- Android release APK: success, ~52.9 MB;
- Python compileall: clean.

Detailed evidence: `docs/testing/pc-version-phase-09.tdd.md`.

## Phase 2 hardware gate

FIFO activation is deliberately deferred until physical XIAO hardware is
available. The ST/Seeed register contract and XIAO INT1 wiring support a future
FIFO/DRDY implementation, but sample pattern alignment, watermark behavior,
timestamp reconstruction, and overrun accounting have not been observed on the
actual board. The release path therefore keeps the lower-risk coherent 12-byte
register burst with BDU + auto-increment and midpoint timestamping.

## Windows packaging environment gate

`flutter doctor -v` on 2026-09-01 reports:

- Flutter 3.41.9 / Dart 3.11.5: available;
- Android toolchain: available;
- **Visual Studio: not installed**;
- Flutter explicitly requires Visual Studio with the **Desktop development with
  C++** workload for Windows builds.

Therefore `flutter build windows --release` remains an environment blocker, not
a code pass/fail result. No system-wide Visual Studio workload is installed
automatically by this task.

## Definition of done

- Every automated phase has tests and a separate commit.
- Flutter analysis/tests and both firmware environments remain green.
- Simulated fault tests prove fail-closed journal/QC behavior.
- Physical acceptance tooling is ready before hardware execution.
- Windows release packaging remains explicitly blocked until the supported
  Visual Studio C++ toolchain is installed.
- Final physical zero-loss/RF/synchronization claims are withheld until two
  physical XIAO boards pass the prescribed acceptance matrix.
