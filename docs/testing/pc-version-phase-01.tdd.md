# PC version Phase 1 evidence

## Source and user journeys

Source: `pc-version-promt.txt` (local task input; intentionally not committed).

- As a researcher, I can see exactly which mobile capabilities are reusable
  and which desktop acquisition guarantees are missing.
- As an engineer, I have a versioned process, data, IPC, synchronization, and
  failure contract before production code changes.
- As a mobile user, the Android data-collection path remains unchanged.
- As a reviewer, I can distinguish automated evidence from physical hardware
  acceptance.

## Baseline task report

| Guarantee | Command | Type | Result | Evidence |
|---|---|---|---|---|
| XIAO host contracts pass before PC work | `cd Xiao_firmware; python -m pytest test -q` | unit/contract | PASS | `12 passed in 0.24s` |
| M5 host contracts pass before PC work | `cd M5plus2_firmware; python -m pytest test -q` | unit/contract | PASS | `135 passed in 0.50s` |
| Dataset tool baseline passes | `python -m pytest tools/test_process_dataset.py -q` | unit | PASS | `5 passed in 1.73s` |
| Flutter production sources analyze after dependency resolution | `cd app; dart analyze lib` | static | PASS | `No issues found!` |
| Existing Flutter suite passes | `cd app; flutter test --coverage --no-pub --timeout 60s --reporter compact` | unit/widget | PASS | `637 passed`; line coverage `81.83%` (`4643/5674`). Stale synchronous-delivery expectations and a STOP-ack test fixture were corrected before PC production code was added. |
| Existing firmware images compile | `pio run -e left -e right` in each firmware directory | build | BLOCKED | PlatformIO package downloads repeatedly ended with mirror `IncompleteRead` errors before compilation began. No compiler regression was observed. |

## Phase 1 specification

| # | What is guaranteed | Evidence | Result |
|---|---|---|---|
| 1 | Required feature rows compare mobile, existing PC, target PC, and reuse | `docs/pc-version/architecture-and-parity.md` | PASS |
| 2 | The lossless path is outside Flutter and raw samples never depend on UI rendering | Target architecture and lossless-path sections | PASS |
| 3 | Arrival time is diagnostic only; device-to-PC mapping defines synchronized time | Synchronization section | PASS |
| 4 | Journal finalization and incomplete-session recovery are explicit | Journal section | PASS |
| 5 | STOP and QC fail closed and preserve partial data | Lifecycle and QC sections | PASS |
| 6 | Android remains on the existing backend | Delivery boundaries | PASS |

## Baseline RED -> GREEN notes

- RED: 12 provider/presentation tests assumed synchronous stream delivery
  after the sample hub became asynchronous; the re-record fixture also hung
  because it did not simulate firmware `STOP_FIRED` acknowledgements.
- GREEN: affected state tests pass (`44 passed`), the complete RecordPage file
  passes (`23 passed`), and the full Flutter suite passes (`637 passed`).
- The RecordPage fixture now uses a local Material theme, so widget tests do
  not depend on fetching Google Fonts over the network.

## Known gaps before Phase 2

- Retry both firmware builds after PlatformIO's package mirror is healthy.
- No physical XIAO was exercised in Phase 1. Actual negotiated MTU/interval,
  dual-wheel throughput, FIFO behavior, and synchronization precision remain
  unverified.
