# Field Protocol

Current release line: `v1.8.0`.
Canonical procedure: [`docs/data-collection-protocol.md`](../data-collection-protocol.md).

This page is a concise operator summary. Use either the Flutter mobile client or the Python Windows client for a sensor pair; do not connect both clients to the same pair simultaneously.

## Before recording

1. Charge both wheel sensors and verify the intended `1.8.0` firmware is flashed.
2. Mount left/right sensors consistently and securely.
3. Prepare the camera if video is part of the gold-standard workflow.
4. Open one operator client:
   - Mobile: Flutter app on iOS/Android; or
   - Windows: Python Research Edition.
5. Scan/connect both wheels and confirm identity, battery, sample-rate configuration, and health status.
6. Run/confirm clock synchronization before the trial.

## Recording

1. Choose/enter athlete/topic/trial metadata.
2. Start camera recording first when camera alignment is required.
3. Start the WheelAthlete recording workflow.
4. Allow the synchronized countdown/start lifecycle to complete.
5. During acquisition watch sample/loss/queue/sync diagnostics rather than RSSI alone.
6. Stop immediately if the system reports a fatal acquisition/storage condition.
7. Stop the WheelAthlete recording, then stop the camera.

Mark Event is not part of the current recording UI. The countdown/beep and recorded lifecycle timestamps are used for post-processing alignment where applicable.

## After recording

### Mobile

- open the saved session preview;
- inspect quality/statistics;
- export/share CSV/Excel/ZIP as required.

### Windows

- confirm final QC;
- keep the finalized `.waj` journal as the authoritative record;
- export CSV only as a derived analysis artifact;
- recover incomplete `.open` journals through the Diagnostics workflow if needed.

## Acceptance rule

Software/demo/simulation results do not substitute for physical BLE acceptance. Real distance, throughput, and left/right start-skew claims require the hardware acceptance matrix documented under `docs/testing/`.
