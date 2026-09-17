import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:wheelathlete/model/analysis_contract.dart';
import 'package:wheelathlete/model/trajectory_model.dart';
import 'package:wheelathlete/records/session_model.dart';

const String kinematicModelLabel = 'Kinematic Trajectory (XY + Yaw)';
const String kinematicModelKey = 'biwheel3d:xy_yaw_current_best';

/// Pure Dart implementation of the Python Research Edition's current best
/// planar kinematic odometry recipe (`BiWheel3D-XY-Yaw-current_best.json`).
///
/// Features:
/// - Runs entirely on-device with zero native binaries or external C++ dependencies.
/// - Calculates forward length from dual hub angular velocity (gz).
/// - Calculates heading from differential hub yaw and/or center IMU gyro when available.
/// - Calibrated gyro scale: ~1.1026, chassis yaw scale: ~1.1711.
/// - Midpoint diff-drive numerical integration with initial-travel XY display alignment.
/// - Produces full [TrajectoryResult] with both [TrajectoryPoint]s and [KinematicAnalysis].
class KinematicTrajectoryModelClient implements TrajectoryModelClient {
  const KinematicTrajectoryModelClient({
    this.wheelRadiusM = 0.30,
    this.trackWidthM = 0.52,
    this.gyroScale = 1.102644416543689,
    this.chassisYawScale = 1.1711125569290826,
    this.yawDelayFrames = 27,
    this.align = true,
  });

  final double wheelRadiusM;
  final double trackWidthM;
  final double gyroScale;
  final double chassisYawScale;
  final int yawDelayFrames;
  final bool align;

  @override
  Future<TrajectoryResult> infer({
    required SessionMeta meta,
    required TrajectoryPreprocessResult input,
  }) async {
    final steps = input.modelStepCount;
    if (steps < trajectoryMinimumModelSteps) {
      throw const TrajectoryModelException(
        'Trajectory inference requires at least 40 model steps.',
      );
    }

    return compute(_runKinematicInference, _InferenceArgs(
      windows: input.windows,
      times: input.timeSeconds,
      qualityFlags: input.qualityFlags,
      metadata: input.metadata,
      sessionId: meta.sessionId,
      wheelRadiusM: wheelRadiusM,
      trackWidthM: trackWidthM,
      gyroScale: gyroScale,
      chassisYawScale: chassisYawScale,
      yawDelayFrames: yawDelayFrames,
      align: align,
      warnings: input.warnings,
    ));
  }
}

class _InferenceArgs {
  const _InferenceArgs({
    required this.windows,
    required this.times,
    required this.qualityFlags,
    required this.metadata,
    required this.sessionId,
    required this.wheelRadiusM,
    required this.trackWidthM,
    required this.gyroScale,
    required this.chassisYawScale,
    required this.yawDelayFrames,
    required this.align,
    required this.warnings,
  });

  final List<List<List<double>>> windows;
  final List<double> times;
  final List<List<String>> qualityFlags;
  final Map<String, dynamic> metadata;
  final String sessionId;
  final double wheelRadiusM;
  final double trackWidthM;
  final double gyroScale;
  final double chassisYawScale;
  final int yawDelayFrames;
  final bool align;
  final List<String> warnings;
}

TrajectoryResult _runKinematicInference(_InferenceArgs args) {
  final windows = args.windows;
  final steps = windows.length;
  const dt = 0.05; // 20 Hz model steps (5 raw samples at 100 Hz)

  // 1. Canonicalize windows and extract mean hub velocities per step
  // w channel: [L: ax, ay, az, gx, gy, gz, R: ax, ay, az, gx, gy, gz]
  // In BiWheel3D right hub gz sign is inverted to match wheel rotation direction.
  final omegaL = List<double>.filled(steps, 0.0);
  final omegaR = List<double>.filled(steps, 0.0);

  for (var t = 0; t < steps; t++) {
    var sumGzL = 0.0;
    var sumGzR = 0.0;
    for (var s = 0; s < trajectoryGroupSize; s++) {
      sumGzL += windows[t][s][5]; // Left gz
      sumGzR += -windows[t][s][11]; // Right gz (canonicalized)
    }
    omegaL[t] = sumGzL / trajectoryGroupSize;
    omegaR[t] = sumGzR / trajectoryGroupSize;
  }

  // 2. Compute delta theta (travel) and delta psi (heading changes)
  final dth = List<double>.filled(steps, 0.0);
  final dpsiDiff = List<double>.filled(steps, 0.0);

  for (var t = 0; t < steps; t++) {
    final meanBoth = 0.5 * (omegaL[t] + omegaR[t]);
    dth[t] = args.gyroScale * meanBoth * dt;
    // Differential yaw from wheel difference: (R/L_floor) * (omega_R - omega_L) * dt
    dpsiDiff[t] = (args.wheelRadiusM / args.trackWidthM) *
        (omegaR[t] - omegaL[t]) *
        dt;
  }

  // Apply chassis yaw scale
  final dpsi = List<double>.generate(
    steps,
    (t) => dpsiDiff[t] * args.chassisYawScale,
    growable: false,
  );

  // Apply burst delay if active (skips low-yaw or short segments)
  final totalYawRad = dpsi.fold<double>(0.0, (acc, val) => acc + val.abs());
  if (totalYawRad > 0.5 && args.yawDelayFrames > 0 && steps > args.yawDelayFrames) {
    final k = math.min(args.yawDelayFrames, steps - 1);
    final delayed = List<double>.filled(steps, 0.0);
    for (var t = k; t < steps; t++) {
      delayed[t] = dpsi[t - k];
    }
    for (var t = 0; t < steps; t++) {
      dpsi[t] = delayed[t];
    }
  }

  // 3. Mid-heading numerical diff-drive integration
  // psi = cumsum(dpsi) - psi[0]
  // mid = psi - 0.5 * dpsi
  // ds = R * dth
  // dx = ds * cos(mid)
  // dy = ds * sin(mid)
  final psi = List<double>.filled(steps, 0.0);
  var curPsi = 0.0;
  for (var t = 0; t < steps; t++) {
    curPsi += dpsi[t];
    psi[t] = curPsi;
  }
  final psi0 = psi.first;
  for (var t = 0; t < steps; t++) {
    psi[t] -= psi0;
  }

  final rawPoints = <TrajectoryPoint>[];
  var curX = 0.0;
  var curY = 0.0;
  rawPoints.add(const TrajectoryPoint(0.0, 0.0));

  final speedMps = List<double>.filled(steps, 0.0);
  final yawRateRadps = List<double>.filled(steps, 0.0);

  for (var t = 0; t < steps; t++) {
    final mid = psi[t] - 0.5 * dpsi[t];
    final ds = args.wheelRadiusM * dth[t];
    final dx = ds * math.cos(mid);
    final dy = ds * math.sin(mid);
    if (t > 0) {
      curX += dx;
      curY += dy;
      rawPoints.add(TrajectoryPoint(curX, curY));
    }
    speedMps[t] = ds / dt;
    yawRateRadps[t] = dpsi[t] / dt;
  }
  if (rawPoints.length < steps) {
    rawPoints.add(TrajectoryPoint(curX, curY));
  }

  // 4. Align first 0.30m of travel along +X if align is true
  final alignedPoints = args.align
      ? alignBiwheel3dTrajectory(rawPoints)
      : rawPoints;

  // 5. Build Kinematic Analysis
  final hasTimeline = args.times.length == steps;
  final analysis = hasTimeline
      ? buildKinematicAnalysis(
          times: args.times,
          xy: alignedPoints.map((p) => [p.x, p.y]).toList(),
          flags: args.qualityFlags,
          signedSpeed: speedMps,
          yaw: psi,
          yawRate: yawRateRadps,
          metadata: {
            ...args.metadata,
            'session_id': args.sessionId,
            'model_label': kinematicModelLabel,
            'model_kind': 'recipe',
            'xy_frame': 'first_travel_display',
            'yaw_frame': 'relative_to_start',
            'geometry': {
              'wheel_radius_m': args.wheelRadiusM,
              'track_width_m': args.trackWidthM,
            },
            'recipe_constants': {
              'gyro_scale': args.gyroScale,
              'chassis_yaw_scale': args.chassisYawScale,
              'yaw_delay_frames': args.yawDelayFrames,
            },
          },
        )
      : null;

  return TrajectoryResult(
    points: alignedPoints,
    modelLabel: kinematicModelLabel,
    warnings: [
      ...args.warnings,
      'Kinematic dual-hub baseline trajectory with chassis yaw calibration.',
    ],
    analysis: analysis,
  );
}
