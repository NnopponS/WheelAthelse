"""Research-grade WheelAthlete Windows acquisition backend.

The package is intentionally UI-free. The Python PySide6 operator UI talks to
the daemon through the versioned localhost IPC layer; BLE callbacks never own
presentation work, and the GUI never owns authoritative raw-data storage.
"""
