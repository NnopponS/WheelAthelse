# PC version Phase 6 — IPC and Flutter Windows backend evidence

## RED -> GREEN

- Python IPC/service integration is covered by the full PC suite: `18 passed`.
- Dart daemon-client tests initially failed on Dart 3 socket stream variance;
  the client now casts `Socket` bytes to `List<int>` before UTF-8 decoding.
- `flutter test test/desktop/daemon_client_test.dart`: `2 passed`.
- `dart analyze lib/desktop test/desktop/daemon_client_test.dart`: no issues.
- `python -m compileall -q tools/pc_acquisition`: clean.

## Implemented guarantees

- The daemon is the owner of BLE, raw sequencing, journal writes, clock fitting,
  START/STOP lifecycle and QC.
- IPC is localhost-only TCP NDJSON, protocol version 1, with a 64 KiB maximum
  message size and mandatory hello/version handshake.
- Commands require request IDs and receive correlated response/error messages.
- `sample_preview` is the only sample-like IPC event and is fed from the
  already-throttled preview sink. Raw 50/100/200 Hz packets remain inside the
  Python process.
- Flutter has a typed daemon client and Riverpod desktop state, but the existing
  mobile `bleRepositoryProvider` is not replaced in this phase.
- Source/development process launching is abstracted so a future bundled daemon
  executable can replace `python -m tools.pc_acquisition.daemon` without
  changing the protocol.
- Scheduled-start acknowledgement timing includes the remaining future lead
  time, preventing the default 3-second T0 from timing out against a 1-second
  post-start ACK margin.

## Build environment

A Windows release build was attempted but the host does not have a Flutter-
supported Visual Studio C++ toolchain. The failure is environmental and is
tracked explicitly; no Windows-build success is claimed.
