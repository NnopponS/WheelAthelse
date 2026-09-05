# WheelAthlete Project State

This directory is intentionally small. Git history is the source of truth for old implementation details; `.project` stores only the current architecture, decisions, status, and a compact milestone history.

## Current product surfaces

WheelAthlete has exactly two user-facing applications:

1. **Flutter Mobile App** — iOS and Android (`app/`)
2. **Python Windows App** — PySide6 GUI + Python acquisition daemon (`tools/pc_gui/`, `tools/pc_acquisition/`)

There is no Flutter Windows application, Flutter Web application, or legacy Tkinter desktop application in the current product.

## Current branch

- Active development branch: `codex/pc-version`
- Remote: `origin` → `NnopponS/WheelAthelse`
- Do not merge or push this branch into `main` unless explicitly requested.

## Current release line

- Product release: `v1.8.0`
- Mobile app: `1.8.0+9`
- Firmware: `1.8.0`
- BLE protocol: `1.8.0`
- Python Windows installer: `1.8.0`

## Files

- `architecture.md` — current runtime architecture and data ownership
- `context.md` — active design decisions and constraints
- `progress.md` — current implementation/verification status
- `history.md` — concise milestone history derived from Git
- `lessons.md` — durable engineering lessons only

Old phase plans, prompts, duplicate trackers, and retired desktop implementation notes were removed on 2026-09-05. They remain recoverable from Git history.
