# WheelAthlete applications

WheelAthlete v1.8.2 is **Windows-first**. This directory contains the active Windows application and the retained Flutter mobile maintenance source.

| Directory | Product | v1.8.2 status |
|---|---|---|
| `wheelathlete_windows/` | **WheelAthlete Windows Research Application** | Active release surface; Python/PySide6 GUI + acquisition daemon |
| `wheelathlete_mobile/` | **WheelAthlete Mobile Application** | Existing Android/iOS source retained for maintenance; no new mobile publication/binary in this release |

The Windows acquisition daemon is the authoritative BLE/raw-recording owner for the current release. Only one operator application should own a given L/R[/C] sensor set at a time.

See [`wheelathlete_windows/README.md`](wheelathlete_windows/README.md) for the active application and the repository-level [`README.md`](../README.md) / [`README.th.md`](../README.th.md) for release scope and system architecture.
