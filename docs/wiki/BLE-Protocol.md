# BLE Protocol

> **Version:** 1.8.0 (dual-wheel lifecycle reliability and acquisition health)
> **Canonical source:** [`docs/ble-protocol.md`](../ble-protocol.md)
> This wiki page is a summary. The canonical doc in the repo is the source
> of truth — firmware and app must both implement it exactly.

## GATT Service

| Name | UUID | Type |
|------|------|------|
| WheelAthlete Service | `0000a1b2-0000-1000-8000-00805f9b34fb` | Primary Service |

UUID base: `0000xxxx-0000-1000-8000-00805f9b34fb` (standard Bluetooth Base),
with `xxxx = a1b2` as the WheelAthlete short handle.

## Characteristics

| Characteristic | UUID suffix | Properties | Direction | Max size |
|---|---|---|---|---|
| IMU Data | `a1b3` | Notify | FW → App | up to MTU-3 |
| Control | `a1b4` | Write + Write Without Response | App → FW | up to 32 B |
| Sync | `a1b5` | Notify + Indicate | FW → App | 28 B |
| Info | `a1b6` | Read | FW → App | 16 B |
| Config | `a1b7` | Read | FW → App | 31 B |
| Battery Level | `2a19` | Read + Notify | FW → App | 1 B |

The app should request MTU 247 on connect to maximize batch size.

## Battery Service (standard BLE, v1.1.0)

Standard Battery Service (UUID `0x180F`) with Battery Level characteristic
(`0x2A19`). Firmware samples and filters battery while idle, then
notifies only on change. Values clamped to 0–100.

## IMU Data (Notify)

### Single sample — 20 bytes, little-endian

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0  | `seq`         | uint32 | Sample sequence (wraps at 2^32) — detects packet loss |
| 4  | `t_device_us` | uint32 | `micros()` on M5 at sample time (µs, wraps at ~71.58 min) |
| 8  | `ax`          | int16  | accel X raw (LSB) |
| 10 | `ay`          | int16  | accel Y raw |
| 12 | `az`          | int16  | accel Z raw |
| 14 | `gx`          | int16  | gyro X raw (LSB) |
| 16 | `gy`          | int16  | gyro Y raw |
| 18 | `gz`          | int16  | gyro Z raw |

### Batch layout

```
[uint8 count][sample_0][sample_1]...[sample_{count-1}]
```

- `count`: 1–N (at MTU 247 → max count = floor((247-3-1)/20) = 12)
- All samples in a batch share consecutive `seq` values
- If the firmware queue overflows (BLE dropped too long), old samples are
  dropped and `drop_count` is reported via Sync events

### Raw → physical conversion

```
accel_g  = raw * accel_scale   # ±2g  → 1/16384 g/LSB
gyro_dps = raw * gyro_scale    # ±2000 dps → 1/16.4 dps/LSB
```

Scale values come from the Info characteristic so firmware can change
ranges without a protocol bump.

## Control (Write)

Every command starts with `uint8 cmd` followed by the command's payload.

| `cmd` | Name | Payload | Response |
|---|---|---|---|
| `0x01` | `START`     | `uint32 target_start_us` (0 = now) | Firmware begins acquisition at `target_start_us` |
| `0x02` | `STOP`      | — | Firmware stops + flushes final batch |
| `0x03` | `SET_RATE`  | `uint16 rate_hz` (50/100/200) | Firmware changes sampling rate (must be stopped) |
| `0x04` | `SYNC_PING` | `uint32 t_app_ms` | Firmware echoes via Sync characteristic |
| `0x05` | `SET_RANGE` | `uint8 accel_range, uint8 gyro_range` | Firmware changes IMU range + updates Info |
| `0x06` | `BEEP`      | `uint8 count, uint16 period_ms` | Firmware emits beep(s) |
| `0x07` | `SET_NAME`  | `char name[24]` (null-padded) | Firmware updates advertised name + Config |
| `0x08` | `SET_WHEEL` | `uint8 wheel_id` (`0x4C`='L', `0x52`='R') | Firmware updates wheel side + Info + Config + advertised name |
| `0x09` | `SET_UTC`   | `uint64 utc_epoch_ms` (LE) | Firmware stores UTC epoch + echoes `UTC_SET` event |
| `0x0A` | `REPLAY_RANGE` | `uint32 start_seq`, `uint16 count` (1–128) | Retransmit retained samples |
| `0x0B` | `SET_BEEP_ENABLED` | `uint8 enabled` (`0`/`1`) | Persist per-board countdown audio; visual countdown stays active |
| `0xFF` | `RESET_SEQ` | — | Firmware resets `seq` to 0 |

Unknown commands → firmware sends `CMD_NACK` via Sync.

> **v1.6.0 STOP finalization:** firmware drains samples that were already in
> flight when acquisition stopped, retains/retries the last IMU batch, and
> emits final `ACQ_HEALTH` followed by `STOP_FIRED` only after the IMU queue and
> retained batch have remained empty for 30 ms. The final produced and notified
> counts therefore describe the complete stopped trial.

### Synchronized start (`target_start_us`)

1. App knows each device's offset from `SYNC_PING`
2. App sets `T_start_phone = now_phone + 5s`
3. App converts to each device's local micros:
   `target_start_us = (T_start_phone - t_app_ref_ms) * 1000 + offset_us + t_device_ref_us`
4. App sends `START` with `target_start_us` to both wheels
5. Firmware waits until `micros() >= target_start_us`, then starts + beeps
6. Jitter = offset error only (typically < 1 sample interval)

### Beep 3-2-1 (audio sync marker)

During countdown, M5 beeps while XIAO flashes its LEDs. Both emit a
`COUNTDOWN_CUE` event so the phone plays the same cue once:
- T-3s, T-2s, T-1s, T-0 (start) — 4 beeps
- 880 Hz countdown + 1320 Hz start
- Beeps are recorded by the camera → align video↔IMU without tapping wheel

## Sync (Notify / Indicate)

### Sync response — 12 bytes

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `t_app_ms`    | uint32 | Echo of app's `SYNC_PING` value |
| 4 | `t_device_us` | uint32 | `micros()` on M5 when ping received |
| 8 | `seq_ping`    | uint32 | Ping sequence (per device, +1 each) |

### Sync events

| Event | Trigger |
|---|---|
| `SYNC_RESPONSE` | Reply to `SYNC_PING` |
| `START_FIRED`   | Scheduled start actually fired |
| `COUNTDOWN_CUE` | M5 beep or XIAO LED cue: `index`, `total`, `duration_ms` |
| `STOP_FIRED`    | Stop command processed |
| `DROP_COUNT`    | Queue overflow — reports cumulative dropped samples |
| `CMD_NACK`      | Unknown command received |
| `UTC_SET`       | `SET_UTC` command processed — echoes stored UTC epoch |
| `ACQ_HEALTH`    | 1 Hz and STOP snapshot of produced/notified samples, sample-queue drops/depth, transport failures, IMU FIFO faults, and FIFO-lost samples |
| `REPLAY_RESULT` | Replay completion (`0x61`; legacy `0x60` reader retained) |

## Info (Read) — 16 bytes

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0  | `wheel_id`     | uint8  | `0x4C`='L', `0x52`='R' |
| 1  | `fw_major`     | uint8  | Firmware major (1) |
| 2  | `fw_minor`     | uint8  | Firmware minor (6) |
| 3  | `fw_patch`     | uint8  | Firmware patch (1) |
| 4  | `accel_range`  | uint8  | Current accel range setting |
| 5  | `gyro_range`   | uint8  | Current gyro range setting |
| 6  | `accel_scale`  | float32 | g/LSB (little-endian) |
| 10 | `gyro_scale`   | float32 | dps/LSB (little-endian) |
| 14 | `reserved`     | uint16 | Reserved (0) |

## Config (Read) — 31 bytes

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0  | `name` | char[24] | Board name (null-padded ASCII) |
| 24 | `wheel_id` | uint8 | Current wheel side |
| 25 | `rate_hz` | uint16 LE | Sampling rate (50/100/200 Hz) |
| 27 | `fw_major` | uint8 | Firmware major version |
| 28 | `fw_minor` | uint8 | Firmware minor version |
| 29 | `fw_patch` | uint8 | Firmware patch version |
| 30 | `beep_enabled` | uint8 | `1` enables countdown audio; `0` disables it |

Config is persisted in NVS by `config_store` and survives power cycles.

## Versioning

The BLE protocol version is independent of firmware/app versions:
- BLE protocol: 1.8.0
- Firmware: 1.8.0
- Mobile app: 1.8.0+9

Any change to packet layout, UUIDs, or command set requires bumping the
BLE protocol version and updating `docs/ble-protocol.md` first.
