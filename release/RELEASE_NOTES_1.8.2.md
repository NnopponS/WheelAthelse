# WheelAthlete 1.8.2

WheelAthlete 1.8.2 is a Windows-first reliability and workflow release. The Flutter mobile project remains in source maintenance and is not available as a v1.8.2 download or update.

## Changes

- Safely finishes active journal writes and stops the installation-owned acquisition daemon before Windows upgrade or uninstall. Setup blocks removal with an actionable message if safe shutdown cannot be confirmed.
- Adds Authenticode signing and verification support for the GUI, daemon, and installer, plus release checksums and a machine-readable signing report.
- Organizes Results as collapsible Day → Experiment → Trials, with distinct day-only, all-recordings, and clear-selection actions. Selection persists by session ID through filtering, view changes, and collapse; export deduplicates recordings and shows count/date scope.
- Uses the high-resolution Windows performance counter for BLE clock observations and scheduled acquisition timing.
- Makes sensor `CHECK` status report the specific data-loss, queue, FIFO, malformed-packet, fatal, or active BLE retry fault while keeping cumulative evidence.
- Shortens model menu names and shows technical/runtime/experimental information in details.
- Adds self-contained model bundles with a versioned manifest, contained artifact paths, preprocessing identity, required roles, units, output capabilities, and runtime requirements. Existing model imports and defaults remain compatible.
- Marks the Flutter mobile application under maintenance and removes mobile artifacts from the v1.8.2 update/release channel.

## Trust and acceptance status

The release must be signed by a trusted Windows publisher certificate. Checksums alone do not remove Microsoft download reputation warnings or bypass an organization’s Application Control policy. The GitHub Release remains gated until `signing-report.json` shows valid signatures and the Windows installed-lifecycle and hardware acceptance checks in `.project/STATUS.md` are complete.
