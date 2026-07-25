# Flutter STOP retry and safety fallback — v1.6.1

Date: 2026-07-21

## Failure evidence

- Android log: Left STOP completed, then Right STOP failed with
  `GATT_INSUFFICIENT_RESOURCES (17)` while both boards remained connected.
- After that exception, the Flutter state closed both local IMU streams and
  returned to Start even though one board continued sending thousands of IMU
  and Sync notifications.
- RED regression tests reproduced both a one-shot STOP write failure and a
  persistent STOP write failure. Before the fix, the transient case ended in
  `LiveAcquisitionStatus.failed` without retry and the persistent case did not
  disconnect the running board.

## Fix

- Serialize STOP writes across the two BLE peripherals.
- Retry a transient STOP write up to three times with bounded backoff.
- After both writes are issued, wait for both `STOP_FIRED` acknowledgements
  concurrently so a lost ACK on one side cannot delay STOP on the other side.
- Keep the local IMU stream alive until the board acknowledges STOP.
- If STOP cannot be written or acknowledged, disconnect only that board so the
  firmware's disconnect handler stops acquisition.
- Apply the same lifecycle to Live and Recording stop paths.

## Verification

- Targeted Flutter state suite: 44 tests passed.
- Dart analyzer over `lib` and the changed state tests: no issues.
- Release build: `app-release.apk`, 52.8 MB.
- Clean Android install: success on Samsung SM-S918B (`R5CW908SDPB`).
- Installed package: `com.wheelathlete.wheelathlete`, version `1.6.1+7`.
- App launched successfully as the top resumed activity with no fatal Flutter
  or Android exception in the post-install log.
- Independent two-board hardware probe after install: Left 190 samples, Right
  190 samples over two seconds; zero sequence gaps, drops, or transport
  failures; both STOP writes completed.

## Remaining physical check

The cleanly installed phone app was granted Nearby Devices permission, but its
post-install scan did not return either board during the verification window.
The same boards were advertising and passed the independent Python probe. A
phone-app Start/Stop capture therefore still requires the boards/phone BLE
scanner to become mutually visible again (for example after a board power
cycle); no app crash or scan exception was logged.
