# Field Protocol

> v0.1.0 — Data Collection MVP
> **Canonical source:** [`docs/data-collection-protocol.md`](../data-collection-protocol.md)

## Equipment checklist

| Item | Qty | Notes |
|------|-----|-------|
| M5StickCPlus2 | 2 | Left + Right wheel |
| USB-C cable | 2 | Charge + flash |
| Power bank | 1 | For sessions > 30 min (M5 battery ~80 mAh) |
| iOS/Android phone | 1 | App installed |
| Video camera | 1 | 60+ fps, with microphone |
| Tripod | 1 | Optional |
| 3M VHB tape or strap | — | Mount M5 on wheel |
| L/R labels | 2 | Stick on each M5 |

## Mounting

### Position
- Mount at **wheel hub** or **spoke** — same position on both wheels
- Avoid spots that impact the ground directly

### Axis orientation
- **Z (az)** — perpendicular to wheel plane (rotation axis)
- **X (ax)** — forward direction
- **Y (ay)** — right side
- Both wheels must match orientation

> If mounted backwards, accel signs flip — but model training still works
> if the protocol is consistent across all sessions.

### Fixing
- Use 3M VHB double-sided tape or a strap
- Must not move during motion — test by shaking before starting
- Add counterweight on the opposite side if wheels become unbalanced

## Camera setup

| Parameter | Recommended | Why |
|-----------|-------------|-----|
| Angle | Side view, both wheels visible | Clear motion capture |
| Distance | 3–5 m | Wide enough to see whole athlete |
| FPS | ≥ 60 fps | Catch fine motion |
| Resolution | ≥ 1080p | See wheel markers |
| Light | Natural or flood | Avoid backlight |
| Audio | Microphone on | Capture beep 3-2-1 for sync |
| Stabilization | Off (if tripod) | Prevent motion blur |

## Step-by-step

### 1. Prepare (5 min)
1. Charge both M5 modules to > 50%
2. Verify latest firmware is flashed
3. Open the WheelAthlete app
4. Mount M5 on both wheels

### 2. Connect + sync (2 min)
1. App → **Connect** tab
2. **Scan** → find `WheelAthlete-L` and `WheelAthlete-R`
3. Connect both
4. Wait for **Clock Sync** to settle (residual < 2 ms) — check Live tab

### 3. Pick topic + trial (1 min)
1. Go to **Record** tab
2. Pick a protocol template (or create a custom topic)
   - Example: `sprint_test`, `athlete_A`, `calibration_01`
3. Trial number auto-increments (e.g. `trial_01`)
4. (Optional) Set sample rate: 100 Hz default, or 50/200 Hz

### 4. Start camera (30 s before)
1. Set up camera per above
2. **Press record on camera BEFORE pressing Start in the app**
3. Say the session name aloud: "sprint_test trial_01 starting now"
   (this audio is in the video for cross-check)

### 5. Start recording (countdown + beep)
1. App → **Start Recording**
2. 5-second countdown + **beep 3-2-1** from both M5 speakers
   - Beeps are in the camera audio = sync marker
3. After final beep → both wheels begin acquisition simultaneously

### 6. During recording
- Watch realtime metrics on Record tab (sample count, elapsed)
- (Mark Event is removed in v0.1.0 — beep + camera audio is the sync source)
- If problems (BLE drop, low battery) → press **Stop** immediately

### 7. Stop recording
1. **Stop Recording** in app
2. System stops both wheels + writes CSV + meta.json
3. "Session saved" screen shows summary (samples, duration, sync quality)
4. Stop camera

### 8. Preview + export
1. Tap **Preview** on the stopped view, or open from Browse
2. Scrub the chart, check stats, verify quality badge
3. **Export** → CSV or Excel
4. **Share** via OS share sheet (AirDrop, email, cloud drive)

## File naming

| File | Convention |
|------|------------|
| Session CSV | `session_<id>.csv` (timestamp-based ID) |
| Session meta | `session_<id>_meta.json` |
| Camera video | `<topic>_trial_<NN>.mp4` (set manually; record in meta.json `cameraVideoFilename`) |

## Quality checklist

Before considering a session good:
- [ ] Sync quality badge = green (< 2 ms)
- [ ] No drops (`dropCount = 0` in meta)
- [ ] Both L and R data present in CSV
- [ ] `timestamp_synced_ms` populated for all samples
- [ ] Camera video filename recorded in meta
- [ ] Beep 3-2-1 audible in camera audio

## Troubleshooting

| Problem | Fix |
|---------|-----|
| BLE disconnects | Move phone closer; reduce interference; recharge M5 |
| Poor sync quality | Reconnect to force fresh clock sync estimation |
| One wheel missing data | Check that wheel's battery + connection; re-record |
| M5 turns off mid-session | Battery dead — charge longer or use power bank |
| App can't find sessions | Check storage permissions; look in `WheelAthleteData/` |
