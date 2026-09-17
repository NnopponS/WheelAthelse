import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:wheelathlete/model/analysis_contract.dart';
import 'package:wheelathlete/model/analysis_timing.dart';
import 'package:wheelathlete/model/trajectory_model.dart';
import 'package:wheelathlete/records/session_model.dart';
import 'package:wheelathlete/theme/theme.dart';

const String threeImuV4ModelLabel = '3IMU v4 Kinematic (L/R/C)';
const String threeImuV4ModelKey = 'biwheel3d:three_imu_odometry_v4';

/// Calibrated gains matching BiWheel3D three_imu_odometry_v4 generic calibration.
const double speedGainMpsPerCount = 0.00035686549526615273;
const double centerYawGainRadpsPerCount = 0.001219087923127951;
const double wheelYawGainRadpsPerCount = 0.0007269114453469359;
const double virtualGyroDpsPerCount = 0.06103515625; // 1 / 16.384

/// On-device pure Dart client for 3-IMU wheelchair odometry v4.
///
/// Combines left hub (L), right hub (R), and chair-center (C) IMUs with:
/// 1. Synchronized resampling across all 3 sensors.
/// 2. Stillness & pause detection with variance-guarded zero-rate gyro bias correction
///    (rejects rocking during U-turns).
/// 3. Calibrated forward speed from dual-hub angular velocity.
/// 4. Adaptive center/differential-wheel yaw fusion.
/// 5. Midpoint SE(2) numerical integration.
class ThreeImuTrajectoryModelClient implements TrajectoryModelClient {
  const ThreeImuTrajectoryModelClient({
    this.wheelRadiusM = 0.30,
    this.trackWidthM = 0.52,
    this.align = true,
  });

  final double wheelRadiusM;
  final double trackWidthM;
  final bool align;

  @override
  Future<TrajectoryResult> infer({
    required SessionMeta meta,
    required TrajectoryPreprocessResult input,
  }) async {
    throw const TrajectoryModelException(
      '3-IMU inference requires Left, Right, and Center IMU data. '
      'Call inferFromSamples instead.',
    );
  }

  /// Run end-to-end 3-IMU inference from raw buffered session samples.
  Future<TrajectoryResult> inferFromSamples({
    required SessionMeta meta,
    required List<BufferedSample> samples,
  }) async {
    return compute(_runThreeImuInference, _ThreeImuInferenceArgs(
      samples: samples,
      meta: meta,
      wheelRadiusM: wheelRadiusM,
      trackWidthM: trackWidthM,
      align: align,
    ));
  }
}

class _ThreeImuInferenceArgs {
  const _ThreeImuInferenceArgs({
    required this.samples,
    required this.meta,
    required this.wheelRadiusM,
    required this.trackWidthM,
    required this.align,
  });

  final List<BufferedSample> samples;
  final SessionMeta meta;
  final double wheelRadiusM;
  final double trackWidthM;
  final bool align;
}

TrajectoryResult _runThreeImuInference(_ThreeImuInferenceArgs args) {
  final samples = args.samples;
  final meta = args.meta;

  // 1. Separate samples by wheel role
  final leftSamples = samples.where((s) => s.wheel == WheelSide.left).toList();
  final rightSamples = samples.where((s) => s.wheel == WheelSide.right).toList();
  final centerSamples = samples.where((s) => s.wheel == WheelSide.center).toList();

  if (leftSamples.isEmpty || rightSamples.isEmpty || centerSamples.isEmpty) {
    throw const TrajectoryModelException(
      '3-IMU trajectory inference requires Left (L), Right (R), and Center (C) sensor data.',
    );
  }

  // 2. Prepare timelines using existing AnalysisWheel helper
  final sourceRateHz = meta.sampleRateHz;
  final leftTimeline = prepareAnalysisWheel(
    samples,
    WheelSide.left,
    sourceRateHz,
    utcStartMs: meta.utcStartMs,
  );
  final rightTimeline = prepareAnalysisWheel(
    samples,
    WheelSide.right,
    sourceRateHz,
    utcStartMs: meta.utcStartMs,
  );
  final centerTimeline = prepareAnalysisWheel(
    samples,
    WheelSide.center,
    sourceRateHz,
    utcStartMs: meta.utcStartMs,
  );

  final leftR = leftTimeline.readings;
  final rightR = rightTimeline.readings;
  final centerR = centerTimeline.readings;

  final overlapStart = math.max(
    0.0,
    math.max(
      leftR.first.tSeconds,
      math.max(rightR.first.tSeconds, centerR.first.tSeconds),
    ),
  );
  final overlapEnd = math.min(
    leftR.last.tSeconds,
    math.min(rightR.last.tSeconds, centerR.last.tSeconds),
  );

  if (overlapEnd <= overlapStart) {
    throw const TrajectoryModelException(
      'Sensor timelines do not have an overlapping interval.',
    );
  }

  const targetHz = 100.0;
  const dt = 1.0 / targetHz;
  final sampleCount = (((overlapEnd - overlapStart) * targetHz + 1e-7).floor() + 1);

  if (sampleCount < 40) {
    throw const TrajectoryModelException(
      'Session requires at least 40 overlapping synchronized samples.',
    );
  }

  // 3. Resample all 3 streams onto uniform grid
  final gzLeftCounts = List<double>.filled(sampleCount, 0.0);
  final gzRightCounts = List<double>.filled(sampleCount, 0.0);
  final gzCenterCounts = List<double>.filled(sampleCount, 0.0);

  final gxCenterCounts = List<double>.filled(sampleCount, 0.0);
  final gyCenterCounts = List<double>.filled(sampleCount, 0.0);
  final gxLeftCounts = List<double>.filled(sampleCount, 0.0);
  final gyLeftCounts = List<double>.filled(sampleCount, 0.0);
  final gxRightCounts = List<double>.filled(sampleCount, 0.0);
  final gyRightCounts = List<double>.filled(sampleCount, 0.0);

  final axCenterMps2 = List<double>.filled(sampleCount, 0.0);
  final ayCenterMps2 = List<double>.filled(sampleCount, 0.0);
  final azCenterMps2 = List<double>.filled(sampleCount, 0.0);

  final times = List<double>.filled(sampleCount, 0.0);

  var li = 0, ri = 0, ci = 0;
  for (var i = 0; i < sampleCount; i++) {
    final t = overlapStart + i * dt;
    times[i] = t;

    final lInterp = _interpolateTimed(leftR, t, li);
    li = lInterp.nextIdx;
    final rInterp = _interpolateTimed(rightR, t, ri);
    ri = rInterp.nextIdx;
    final cInterp = _interpolateTimed(centerR, t, ci);
    ci = cInterp.nextIdx;

    // Convert rad/s back to virtual counts: counts = (rad/s * 180 / pi) / virtualGyroDpsPerCount
    const toCounts = (180.0 / math.pi) / virtualGyroDpsPerCount;

    // Invert right wheel gyro to match forward rolling
    gzLeftCounts[i] = lInterp.values[5] * toCounts;
    gzRightCounts[i] = -rInterp.values[5] * toCounts;
    gzCenterCounts[i] = cInterp.values[5] * toCounts;

    gxCenterCounts[i] = cInterp.values[3] * toCounts;
    gyCenterCounts[i] = cInterp.values[4] * toCounts;
    gxLeftCounts[i] = lInterp.values[3] * toCounts;
    gyLeftCounts[i] = lInterp.values[4] * toCounts;
    gxRightCounts[i] = rInterp.values[3] * toCounts;
    gyRightCounts[i] = rInterp.values[4] * toCounts;

    axCenterMps2[i] = cInterp.values[0];
    ayCenterMps2[i] = cInterp.values[1];
    azCenterMps2[i] = cInterp.values[2];
  }

  // 4. Activity magnitude & Stillness detection
  final centerNorm = List<double>.filled(sampleCount, 0.0);
  final wheelNorm = List<double>.filled(sampleCount, 0.0);

  for (var i = 0; i < sampleCount; i++) {
    centerNorm[i] = math.sqrt(
      gxCenterCounts[i] * gxCenterCounts[i] +
      gyCenterCounts[i] * gyCenterCounts[i] +
      gzCenterCounts[i] * gzCenterCounts[i],
    );
    wheelNorm[i] = math.sqrt(0.5 * (
      gxLeftCounts[i] * gxLeftCounts[i] +
      gyLeftCounts[i] * gyLeftCounts[i] +
      gzLeftCounts[i] * gzLeftCounts[i] +
      gxRightCounts[i] * gxRightCounts[i] +
      gyRightCounts[i] * gyRightCounts[i] +
      gzRightCounts[i] * gzRightCounts[i]
    ));
  }

  final sortedC = List<double>.from(centerNorm)..sort();
  final sortedW = List<double>.from(wheelNorm)..sort();
  final qIdx = (sampleCount * 0.035).floor().clamp(0, sampleCount - 1);

  final cFloor = 10.0;
  final wFloor = 35.0;
  final cThr = math.max(cFloor, sortedC[qIdx]);
  final wThr = math.max(wFloor, sortedW[qIdx]);

  final rawPause = List<bool>.generate(
    sampleCount,
    (i) => centerNorm[i] <= cThr && wheelNorm[i] <= wThr,
  );

  // Close short gaps <= 12 samples
  final closedPause = List<bool>.from(rawPause);
  var gapStart = -1;
  for (var i = 0; i < sampleCount; i++) {
    if (!closedPause[i]) {
      if (gapStart < 0) gapStart = i;
    } else {
      if (gapStart >= 0) {
        final gapLen = i - gapStart;
        if (gapLen <= 12 && gapStart > 0) {
          for (var g = gapStart; g < i; g++) {
            closedPause[g] = true;
          }
        }
        gapStart = -1;
      }
    }
  }

  // Enforce min pause duration >= 45 samples (0.45s)
  final validPause = List<bool>.filled(sampleCount, false);
  var pStart = -1;
  for (var i = 0; i < sampleCount; i++) {
    if (closedPause[i]) {
      if (pStart < 0) pStart = i;
    } else {
      if (pStart >= 0) {
        if (i - pStart >= 45) {
          for (var p = pStart; p < i; p++) {
            validPause[p] = true;
          }
        }
        pStart = -1;
      }
    }
  }
  if (pStart >= 0 && sampleCount - pStart >= 45) {
    for (var p = pStart; p < sampleCount; p++) {
      validPause[p] = true;
    }
  }

  // 5. Variance-guarded Zero-Rate Gyro Bias Estimation
  // Reject false pause anchors when athlete torso rocks/leans at U-turns
  const maxCenterStdCounts = 5.0;
  final anchorTimes = <double>[];
  final anchorBiases = <double>[];

  pStart = -1;
  for (var i = 0; i <= sampleCount; i++) {
    final isPause = (i < sampleCount) && validPause[i];
    if (isPause) {
      if (pStart < 0) pStart = i;
    } else {
      if (pStart >= 0) {
        final segLen = i - pStart;
        if (segLen >= 30) {
          var sumGz = 0.0;
          for (var j = pStart; j < i; j++) {
            sumGz += gzCenterCounts[j];
          }
          final meanGz = sumGz / segLen;

          var sumSq = 0.0;
          for (var j = pStart; j < i; j++) {
            final diff = gzCenterCounts[j] - meanGz;
            sumSq += diff * diff;
          }
          final stdGz = math.sqrt(sumSq / segLen);

          // Variance guard: accept anchor ONLY if gyro variance is low
          if (stdGz <= maxCenterStdCounts) {
            final midIdx = (pStart + i) ~/ 2;
            anchorTimes.add(times[midIdx]);
            anchorBiases.add(meanGz);
          }
        }
        pStart = -1;
      }
    }
  }

  // Interpolate gyro bias trace across session
  final centerBiasTrace = List<double>.filled(sampleCount, 0.0);
  if (anchorTimes.isNotEmpty) {
    for (var i = 0; i < sampleCount; i++) {
      final t = times[i];
      if (t <= anchorTimes.first) {
        centerBiasTrace[i] = anchorBiases.first;
      } else if (t >= anchorTimes.last) {
        centerBiasTrace[i] = anchorBiases.last;
      } else {
        var idx = 0;
        while (idx < anchorTimes.length - 1 && anchorTimes[idx + 1] < t) {
          idx++;
        }
        final t0 = anchorTimes[idx], t1 = anchorTimes[idx + 1];
        final b0 = anchorBiases[idx], b1 = anchorBiases[idx + 1];
        final alpha = (t - t0) / (t1 - t0);
        centerBiasTrace[i] = b0 + alpha * (b1 - b0);
      }
    }
  }

  // Compute initial gravity axis from stillness
  final pauseAx = <double>[];
  final pauseAy = <double>[];
  final pauseAz = <double>[];
  for (var i = 0; i < sampleCount; i++) {
    if (validPause[i]) {
      pauseAx.add(axCenterMps2[i]);
      pauseAy.add(ayCenterMps2[i]);
      pauseAz.add(azCenterMps2[i]);
    }
  }
  var gInitX = pauseAx.isNotEmpty ? _median(pauseAx) : _median(axCenterMps2);
  var gInitY = pauseAy.isNotEmpty ? _median(pauseAy) : _median(ayCenterMps2);
  var gInitZ = pauseAz.isNotEmpty ? _median(pauseAz) : _median(azCenterMps2);
  var initGNorm = math.sqrt(gInitX * gInitX + gInitY * gInitY + gInitZ * gInitZ);
  final gMag = initGNorm > 1e-6 ? initGNorm : 9.80665;
  if (initGNorm > 1e-6) {
    gInitX /= initGNorm;
    gInitY /= initGNorm;
    gInitZ /= initGNorm;
  } else {
    gInitX = 0.0;
    gInitY = 0.0;
    gInitZ = 1.0;
  }

  // 6. Compute Speed, Dynamic Attitude Decoupling & Adaptive Yaw Fusion
  final speedMps = List<double>.filled(sampleCount, 0.0);
  final yawRateRadps = List<double>.filled(sampleCount, 0.0);

  var gCurrX = gInitX, gCurrY = gInitY, gCurrZ = gInitZ;
  const tau = 2.0;
  final alpha = dt / (tau + dt);
  const scaleGyro = (math.pi / 180.0) * virtualGyroDpsPerCount;

  for (var i = 0; i < sampleCount; i++) {
    // Gyro angular velocities in rad/s
    final gzCenterCorrected = gzCenterCounts[i] - centerBiasTrace[i];
    final wx = gxCenterCounts[i] * scaleGyro;
    final wy = gyCenterCounts[i] * scaleGyro;
    final wz = gzCenterCorrected * scaleGyro;

    // Body tilt integration: d(g_body)/dt = g_body x omega
    final dGx = (gCurrY * wz - gCurrZ * wy) * dt;
    final dGy = (gCurrZ * wx - gCurrX * wz) * dt;
    final dGz = (gCurrX * wy - gCurrY * wx) * dt;
    gCurrX += dGx;
    gCurrY += dGy;
    gCurrZ += dGz;

    // Fused with accelerometer gravity vector when dynamic acceleration is low
    final ax = axCenterMps2[i], ay = ayCenterMps2[i], az = azCenterMps2[i];
    final aNorm = math.sqrt(ax * ax + ay * ay + az * az);
    if ((aNorm - gMag).abs() / math.max(gMag, 1.0) < 0.15 && aNorm > 1e-6) {
      gCurrX = (1.0 - alpha) * gCurrX + alpha * (ax / aNorm);
      gCurrY = (1.0 - alpha) * gCurrY + alpha * (ay / aNorm);
      gCurrZ = (1.0 - alpha) * gCurrZ + alpha * (az / aNorm);
    }

    final curGNorm = math.sqrt(gCurrX * gCurrX + gCurrY * gCurrY + gCurrZ * gCurrZ);
    if (curGNorm > 1e-6) {
      gCurrX /= curGNorm;
      gCurrY /= curGNorm;
      gCurrZ /= curGNorm;
    }

    // Dynamic pitch/roll decoupled center yaw rate (dot product with gravity unit vector)
    final centerDynCounts = gxCenterCounts[i] * gCurrX + gyCenterCounts[i] * gCurrY + gzCenterCorrected * gCurrZ;

    // Forward speed from average wheel angular velocity
    final speed = speedGainMpsPerCount * 0.5 * (gzLeftCounts[i] + gzRightCounts[i]);
    speedMps[i] = speed;

    // Yaw rates in rad/s
    final centerYawRate = centerYawGainRadpsPerCount * centerDynCounts;
    final wheelYawRate = wheelYawGainRadpsPerCount * (gzRightCounts[i] - gzLeftCounts[i]);

    // Adaptive fusion weights
    final disagreementDegS = (centerYawRate - wheelYawRate).abs() * (180.0 / math.pi);
    final absCenterDegS = centerYawRate.abs() * (180.0 / math.pi);

    var wCenter = 0.95;
    if (absCenterDegS > 28.0) {
      wCenter = 1.00;
    }
    final bonus = (disagreementDegS / 24.0).clamp(0.0, 1.0) * 0.05;
    wCenter = math.min(1.0, wCenter + bonus);

    final fusedYawRate = wCenter * centerYawRate + (1.0 - wCenter) * wheelYawRate;
    yawRateRadps[i] = fusedYawRate;
  }

  // 7. Midpoint SE(2) Numerical Integration
  final headingRad = List<double>.filled(sampleCount, 0.0);
  final rawPoints = <TrajectoryPoint>[];
  rawPoints.add(const TrajectoryPoint(0.0, 0.0));

  var curHeading = 0.0;
  var curX = 0.0;
  var curY = 0.0;

  for (var i = 1; i < sampleCount; i++) {
    final dHeading = yawRateRadps[i] * dt;
    final midHeading = curHeading + 0.5 * dHeading;
    curHeading += dHeading;
    headingRad[i] = curHeading;

    final ds = speedMps[i] * dt;
    curX += ds * math.cos(midHeading);
    curY += ds * math.sin(midHeading);
    rawPoints.add(TrajectoryPoint(curX, curY));
  }

  // Display alignment
  final alignedPoints = args.align ? alignBiwheel3dTrajectory(rawPoints) : rawPoints;

  // 8. Build Kinematic Analysis
  final analysis = buildKinematicAnalysis(
    times: times,
    xy: alignedPoints.map((p) => [p.x, p.y]).toList(),
    flags: List.generate(sampleCount, (_) => const <String>[]),
    signedSpeed: speedMps,
    yaw: headingRad,
    yawRate: yawRateRadps,
    metadata: {
      'session_id': meta.sessionId,
      'model_label': threeImuV4ModelLabel,
      'model_kind': 'three_imu_v4',
      'xy_frame': 'initial_chair_heading',
      'yaw_frame': 'initial_chair_heading',
      'stillness_anchors_count': anchorTimes.length,
      'speed_gain': speedGainMpsPerCount,
      'center_yaw_gain': centerYawGainRadpsPerCount,
      'wheel_yaw_gain': wheelYawGainRadpsPerCount,
    },
  );

  return TrajectoryResult(
    points: alignedPoints,
    modelLabel: threeImuV4ModelLabel,
    warnings: [
      '3-IMU v4 Kinematic odometry: Left, Right, and Center IMUs with variance-guarded stillness filter.',
      'Anchored  verified zero-rate stillness intervals.',
    ],
    analysis: analysis,
  );
}

class _TimedInterpResult {
  const _TimedInterpResult(this.values, this.nextIdx);
  final List<double> values;
  final int nextIdx;
}

double _median(List<double> values) {
  if (values.isEmpty) return 0.0;
  final sorted = List<double>.from(values)..sort();
  final mid = sorted.length ~/ 2;
  if (sorted.length % 2 == 1) {
    return sorted[mid];
  }
  return 0.5 * (sorted[mid - 1] + sorted[mid]);
}

_TimedInterpResult _interpolateTimed(
  List<TimedAnalysisReading> readings,
  double t,
  int startIdx,
) {
  if (readings.isEmpty) return const _TimedInterpResult([0, 0, 0, 0, 0, 0], 0);
  if (t <= readings.first.tSeconds) {
    final r = readings.first;
    return _TimedInterpResult([r.axMps2, r.ayMps2, r.azMps2, r.gxRadps, r.gyRadps, r.gzRadps], 0);
  }
  if (t >= readings.last.tSeconds) {
    final r = readings.last;
    return _TimedInterpResult([r.axMps2, r.ayMps2, r.azMps2, r.gxRadps, r.gyRadps, r.gzRadps], readings.length - 1);
  }
  var idx = startIdx.clamp(0, readings.length - 2);
  while (idx < readings.length - 2 && readings[idx + 1].tSeconds < t) {
    idx++;
  }
  final r0 = readings[idx];
  final r1 = readings[idx + 1];
  final span = r1.tSeconds - r0.tSeconds;
  final frac = span > 1e-9 ? (t - r0.tSeconds) / span : 0.0;

  return _TimedInterpResult([
    r0.axMps2 + frac * (r1.axMps2 - r0.axMps2),
    r0.ayMps2 + frac * (r1.ayMps2 - r0.ayMps2),
    r0.azMps2 + frac * (r1.azMps2 - r0.azMps2),
    r0.gxRadps + frac * (r1.gxRadps - r0.gxRadps),
    r0.gyRadps + frac * (r1.gyRadps - r0.gyRadps),
    r0.gzRadps + frac * (r1.gzRadps - r0.gzRadps),
  ], idx);
}

