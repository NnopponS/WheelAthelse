"""Research-grade WheelAthlete Windows acquisition backend.

The package is intentionally UI-free.  Flutter Windows talks to the daemon
through the versioned IPC layer added in later phases; BLE callbacks never own
recording storage or presentation work.
"""
