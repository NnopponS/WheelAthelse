# WheelAthlete 1.8.2

WheelAthlete 1.8.2 is the consolidated Windows-first reliability, acquisition and release-engineering update. Mobile development is not part of this publication and no mobile binary/update asset is provided.

## Highlights

- Safely finalizes an active `.waj` journal and shuts down the installation-owned acquisition daemon before Windows upgrade/uninstall; setup stops instead of replacing files when safe shutdown cannot be confirmed.
- Preserves recordings, logs and custom/seeded models across the installed lifecycle.
- Organizes Results as collapsible Day -> Experiment -> Trial groups with persistent session-ID selection, day/all/clear actions and deduplicated export.
- Uses high-resolution Windows performance-counter timing for acquisition clock observations and scheduled starts.
- Reports concrete sensor/data-loss/queue/FIFO/malformed/retry faults instead of an unexplained generic `CHECK` state.
- Supports optional sensor role `C` (`0x43`) for chair-center acquisition/storage with +Z down. XIAO C identity is green; existing production trajectory models remain L/R-only.
- Adds concise model presentation and a contained, versioned `wheelathlete-model.json` bundle contract while keeping the frozen classical L/R model as the installed default.
- Hardens Windows release signing across packaged EXE/DLL/PYD/PowerShell components, generated uninstaller and installer, with exact publisher validation, timestamps, checksums and a fail-closed machine-readable signing report.

## Verification boundary

Fresh 2026-09-10 consolidation verification passed **195/195** Windows tests, **4/4** Windows packaging-layout tests, **19/19** XIAO host tests, **147/147** M5 host tests, release-manifest tests, Python compile checks, project hygiene and diff checks. Fresh PlatformIO build artifacts were produced for L/R/C on both XIAO and M5 targets. A complete unsigned-local Windows packaging lifecycle also completed through PyInstaller, Inno Setup, portable ZIP, checksums and schema-2 signing-report generation; as expected without a trusted publisher identity, that report remains `public_release_ready=false` and those local artifacts are not public release assets.

The center XIAO 1.8.2 post-flash observation reached 1,780.865 s before the board was removed, with zero observed sequence/malformed/queue/notification/FIFO fault counters in the final 1,750 s snapshot. The missing final STOP/QC/reopen/export sequence and simultaneous L/R/C run remain deferred hardware acceptance, not a software-release claim.

## Trust status

This GitHub Release remains **source-only** until a trusted Windows publisher identity is available. No installer, portable archive or `latest.json` should be attached while the signing report cannot return `public_release_ready=true`.

Checksums establish artifact integrity but do not establish publisher trust or bypass SmartScreen/Application Control policy. Organization allowlists may still impose stricter rules even on correctly signed software.

## Publication scope

The release publishes the integrated root source only. It does not publish generated research data, local evidence, signing material, `BiWheel3D`, or any mobile installation/update asset.
