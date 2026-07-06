# Time Synchronization

> v0.1.0 — Data Collection MVP

## The problem

Two M5StickCPlus2 modules have independent `micros()` clocks that:
- Start at different times
- Drift at different rates (crystal tolerance)
- Wrap at ~71.58 minutes (uint32 microseconds)

BLE notify latency varies per connection and per packet, so using raw
phone receive timestamps is not accurate enough for cross-wheel alignment.

## The solution

The **phone is the common reference**. It already talks to both wheels,
so it's the cheapest accurate clock. No NTP, no RTC hardware needed.

The app runs an NTP/PTP-lite estimation over BLE:

### 1. Offset estimation

```
App sends SYNC_PING with t_app_ms (phone epoch ms)
Firmware echoes back: t_app_ms (echo) + t_device_us (M5 micros at receive)
App measures round-trip time (RTT)
App keeps the sample with the lowest RTT (least noise)
App estimates: offset_us = t_device_us - (t_app_ms * 1000) - RTT/2
```

Multiple pings are sent; the lowest-RTT sample wins.

### 2. Drift correction

Over a session, the app collects many `(t_device_us, t_app_ms)` pairs and
fits a linear model:

```
t_device_us = a + b * t_app_ms
```

- `a` = offset at sync reference time
- `b` = drift rate (slope)

Every sample is then mapped to the common UTC timeline:

```
timestamp_synced_ms = (t_device_us - a) / b / 1000 + utc_epoch_ms
```

Where `utc_epoch_ms` is set via the `SET_UTC` command at the start of the
session (the phone's UTC epoch milliseconds).

### 3. Scheduled synchronized start

To make both wheels begin acquisition at the same instant:

1. App knows each wheel's offset from step 1
2. App computes `T_start_phone = now_phone + 5s` (5-second countdown)
3. App converts `T_start_phone` to each wheel's local micros:
   ```
   target_start_us = (T_start_phone - t_app_ref_ms) * 1000
                     + offset_us + t_device_ref_us
   ```
4. App sends `START` with `target_start_us` to both wheels
5. Each wheel's firmware waits until `micros() >= target_start_us`, then
   begins acquisition
6. Jitter = offset estimation error only (typically < 1 sample interval,
   i.e. < 10 ms at 100 Hz)

### 4. Beep 3-2-1 audio marker

During the 5-second countdown, both M5 speakers beep:
- T-3s, T-2s, T-1s, T-0 (start) — 4 beeps
- 880 Hz for countdown beeps, 1320 Hz for the start beep

These beeps are:
- Recorded by the camera's microphone
- Logged as known-time events in the IMU stream

This lets you align video↔IMU **without tapping the wheel** — just find
the beep peaks in the camera audio and match them to the known start time.

## Quality metric

Sync quality is reported as **drift residual RMS in milliseconds** — the
RMS of the residuals after the linear drift fit.

| Drift RMS | Quality | Badge color |
|-----------|---------|-------------|
| `< 2 ms`  | good    | green       |
| `2–5 ms`  | fair    | amber       |
| `> 5 ms`  | poor    | red         |
| `null`    | unknown | grey        |

The app shows this as a colored badge next to each session in Browse and
in the preview page summary.

## When sync runs

- **On connect** — initial offset estimation (multiple pings)
- **Before recording** — fresh offset + drift estimation
- **During recording** — periodic re-estimation (drift can change with
  temperature)

## What can go wrong

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Poor quality badge (> 5 ms) | BLE connection unstable | Move phone closer, reduce interference |
| Large offset | First ping had high RTT | Reconnect to force fresh estimation |
| Drift increasing over time | Temperature change | App re-estimates periodically; long sessions may still drift |
| Samples missing | Queue overflow (BLE dropped too long) | Check `dropCount` in meta.json |

## Implementation

- **Firmware:** `SYNC_PING` captured in NimBLE callback (lowest-latency
  path). Response sent via Sync characteristic notify.
- **App:** `lib/state/sync_engine.dart` — manages ping scheduling, RTT
  measurement, offset/drift fitting, and `timestamp_synced_ms` computation
  for every incoming sample.
