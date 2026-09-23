# WheelAthlete 1.8.4

## Windows recording reliability

- XIAO firmware 1.8.3 now fills packets to the negotiated MTU when its sample queue backs up, reducing BLE packet overhead during recovery from short congestion. Normal batch timing remains unchanged while the queue is healthy. It also preserves a valid saved L/R/C identity across firmware uploads.
- The Results page and preview expose stored QC reasons. Model results warn when the source recording is invalid or degraded, and the loss summary avoids adding overlapping sequence and firmware counters together.
- The acquisition countdown waits for the daemon's confirmed recording-start event before scheduling the PC start cue. The cue plays one second after recording begins; a missed device start no longer sounds like a successful start.

## Model and Results

- The Model page can show true XYZ trajectories from an explicitly selected compatible local L/R/C research model. It reports vertical range and includes Z in trajectory CSV exports when available; XY-only results clearly identify Z as unavailable.
- Orbitable 3D is selected for XYZ output when no comparison overlay is enabled. When comparisons are selected, the page opens the 2D overlay view so the selected model/C3D comparisons stay visible.
- Results and Model pages retain readable access to controls and long content on smaller windows.

## Scope and limitations

- The local SIF 3D model remains an optional research model. It is not bundled or selected as the installed application's default, and its display is not a claim of prospective physical accuracy.
- The XIAO packet-size change provides capacity headroom; it cannot recover samples already lost or guarantee zero loss when sustained BLE throughput is below the configured sample rate.
- XIAO firmware changes are provided as source/builds; the Windows installer does not flash the boards. M5 firmware remains at 1.8.2.
- Release assets contain Windows binaries only. No mobile binary is included.
