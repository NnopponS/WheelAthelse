"""WheelAthlete Python Research Edition desktop UI.

The Qt UI is intentionally a separate process from the lossless acquisition
service in :mod:`tools.pc_acquisition`. Only throttled preview/status traffic
crosses the localhost IPC boundary; raw IMU data remains daemon-owned.
"""

__version__ = "0.1.0"
