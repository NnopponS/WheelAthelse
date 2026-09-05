# Time Synchronization

Current release line: `v1.8.0`.

Each wheel sensor has an independent device clock. BLE receive latency/jitter means raw client receive time alone is not accurate enough for cross-wheel alignment.

## Common model

Both operator clients estimate the relationship between each device clock and a common client-side timeline using low-RTT synchronization exchanges and drift fitting. The exact runtime implementation differs by platform, but the protocol semantics are shared.

Core flow:

1. send synchronization pings to each connected wheel;
2. observe device time plus client send/receive timing;
3. retain low-RTT observations to reduce transport noise;
4. fit/maintain clock mapping and drift;
5. schedule recording start against the common client timeline;
6. require firmware lifecycle acknowledgement;
7. map samples onto a synchronized timeline with clear provenance.

## Mobile

The Flutter app performs synchronization directly over its BLE connections and records synchronized timestamps in mobile session data/metadata.

## Windows

The Python acquisition daemon owns synchronization. The PySide6 GUI only requests sync/record actions and displays resulting quality metrics; it does not compute the authoritative raw-data timing path.

## Camera alignment

The countdown/beep workflow can provide an audio event visible in camera recording for post-processing alignment. Mark Event is no longer part of the current recording UI.

## Quality rule

Synchronization quality must be evaluated from measured RTT/residual/drift/lifecycle evidence. RSSI is useful RF context but is not a synchronization-quality metric.

See `docs/ble-protocol.md` for packet/event details and `.project/architecture.md` for the current client architecture.
