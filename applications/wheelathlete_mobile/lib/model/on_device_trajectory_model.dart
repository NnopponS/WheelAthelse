import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:wheelathlete/model/analysis_contract.dart';
import 'package:flutter/services.dart';
import 'package:onnxruntime_v2/onnxruntime_v2.dart';
import 'package:wheelathlete/model/trajectory_model.dart';
import 'package:wheelathlete/records/session_model.dart';

const String biwheel3dMobileModelAsset =
    'assets/models/wheelathlete_biwheel3d_m4.onnx';
const String biwheel3dMobileModelLabel = 'BiWheel3D M4 - On-device';

/// Runs the legacy experimental XY-only M4 graph entirely on the phone.
/// It is not the P2 candidate and has no validated chair-yaw output.
///
/// The bundled ONNX graph contains the original feature normalization and
/// trained TCN + bidirectional LSTM + physics integration. Dart performs only
/// the deterministic `(T,5,12) -> (T,90)` feature extraction and final XY
/// display alignment that the Python reference pipeline performs outside the
/// network.
class OnDeviceTrajectoryModelClient implements TrajectoryModelClient {
  OnDeviceTrajectoryModelClient({AssetBundle? assetBundle})
    : _assetBundle = assetBundle ?? rootBundle;

  final AssetBundle _assetBundle;
  Future<OrtSession>? _sessionFuture;
  bool _disposed = false;
  Completer<void>? _active;
  String? _modelSha256;

  @override
  Future<TrajectoryResult> infer({
    required SessionMeta meta,
    required TrajectoryPreprocessResult input,
  }) async {
    if (_disposed || _active != null) {
      throw const TrajectoryModelException(
        'Model is disposed or already running.',
      );
    }
    final done = Completer<void>();
    _active = done;
    try {
      return await _infer(meta: meta, input: input);
    } finally {
      _active = null;
      done.complete();
    }
  }

  Future<TrajectoryResult> _infer({
    required SessionMeta meta,
    required TrajectoryPreprocessResult input,
  }) async {
    if (_disposed) {
      throw const TrajectoryModelException(
        'The on-device trajectory model has already been disposed.',
      );
    }
    final steps = input.modelStepCount;
    final hasTimeline =
        input.timeSeconds.isNotEmpty || input.qualityFlags.isNotEmpty;
    if (hasTimeline &&
        (input.timeSeconds.length != steps ||
            input.qualityFlags.length != steps)) {
      throw const TrajectoryModelException(
        'Prepared timeline and model-window lengths differ.',
      );
    }
    final features = await compute(extractBiwheel3dFeatures, input);
    if (features.length != steps * biwheel3dFeatureDim) {
      throw const TrajectoryModelException(
        'BiWheel3D feature tensor has an unexpected size.',
      );
    }

    if (_disposed) throw const TrajectoryModelException('Analysis cancelled.');
    final session = await (_sessionFuture ??= _loadSession());
    if (_disposed) throw const TrajectoryModelException('Analysis cancelled.');
    final tensor = OrtValueTensor.createTensorWithDataList(features, [
      1,
      steps,
      biwheel3dFeatureDim,
    ]);
    final runOptions = OrtRunOptions();
    List<OrtValue?>? outputs;
    try {
      outputs = await session.runAsyncWithTimeout(
        runOptions,
        {'features': tensor},
        const Duration(seconds: 90),
        const ['xy'],
      );
      if (outputs == null || outputs.isEmpty || outputs.first == null) {
        throw const TrajectoryModelException(
          'The on-device model returned no trajectory output.',
        );
      }
      final raw = outputs.first!.value;
      final points = _parseOutput(raw, expectedSteps: steps);
      final aligned = alignBiwheel3dTrajectory(points);
      final analysisJson = hasTimeline
          ? await compute(_buildOnnxAnalysis, <String, dynamic>{
              'times': input.timeSeconds,
              'xy': aligned.map((p) => [p.x, p.y]).toList(),
              'flags': input.qualityFlags,
              'metadata': <String, dynamic>{
                ...input.metadata,
                'session_id': meta.sessionId,
                'model_label': biwheel3dMobileModelLabel,
                'model_kind': 'onnx',
                'model_sha256': _modelSha256,
                'xy_frame': 'first_travel_display',
                'yaw_frame': 'unavailable',
                'geometry': {
                  'wheel_radius_m': .30,
                  'track_width_m': .52,
                  'camber_rad': 0.0,
                  'source': 'inherited_assumptions',
                },
                'warnings': input.warnings,
              },
            })
          : null;
      if (_disposed) {
        throw const TrajectoryModelException('Analysis cancelled.');
      }
      return TrajectoryResult(
        points: aligned,
        modelLabel: biwheel3dMobileModelLabel,
        warnings: List.unmodifiable([
          ...input.warnings,
          if (!hasTimeline)
            'Legacy prepared tensor has no original time/QC provenance; timeline and derived kinematics are unavailable.',
        ]),
        analysis: analysisJson == null
            ? null
            : KinematicAnalysis.fromJson(analysisJson),
      );
    } on TrajectoryModelException {
      rethrow;
    } on Object catch (error) {
      throw TrajectoryModelException(
        'On-device BiWheel3D inference failed: $error',
      );
    } finally {
      tensor.release();
      runOptions.release();
      for (final output in outputs ?? const <OrtValue?>[]) {
        output?.release();
      }
    }
  }

  Future<OrtSession> _loadSession() async {
    try {
      OrtEnv.instance.init();
      final bytes = await _assetBundle.load(biwheel3dMobileModelAsset);
      final modelBytes = Uint8List.sublistView(bytes);
      _modelSha256 = sha256.convert(modelBytes).toString();
      final options = OrtSessionOptions();
      try {
        // CPU is intentionally the baseline provider. It is deterministic and
        // available on both Android and iOS. Native ORT still uses optimized
        // threads internally, while runAsync keeps the Flutter UI responsive.
        options.setIntraOpNumThreads(0);
        return OrtSession.fromBuffer(modelBytes, options);
      } finally {
        options.release();
      }
    } on Object catch (error) {
      throw TrajectoryModelException(
        'Could not load the bundled BiWheel3D model: $error',
      );
    }
  }

  static List<TrajectoryPoint> _parseOutput(
    Object? raw, {
    required int expectedSteps,
  }) {
    if (raw is! List || raw.length != 1 || raw.first is! List) {
      throw const TrajectoryModelException(
        'The on-device model returned an invalid XY tensor.',
      );
    }
    final rows = raw.first as List;
    if (rows.length != expectedSteps) {
      throw TrajectoryModelException(
        'The on-device model returned ${rows.length} points for '
        '$expectedSteps input steps.',
      );
    }
    final points = <TrajectoryPoint>[];
    for (final row in rows) {
      if (row is! List || row.length < 2 || row[0] is! num || row[1] is! num) {
        throw const TrajectoryModelException(
          'The on-device model returned invalid XY values.',
        );
      }
      final x = (row[0] as num).toDouble();
      final y = (row[1] as num).toDouble();
      if (!x.isFinite || !y.isFinite) {
        throw const TrajectoryModelException(
          'The on-device model returned non-finite XY values.',
        );
      }
      points.add(TrajectoryPoint(x, y));
    }
    return List.unmodifiable(points);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _active?.future;
    final future = _sessionFuture;
    _sessionFuture = null;
    if (future != null) {
      try {
        final session = await future;
        await session.release();
      } on Object {
        // A failed lazy load has no native session to release.
      }
    }
  }
}

Map<String, dynamic> _buildOnnxAnalysis(Map<String, dynamic> value) =>
    buildKinematicAnalysis(
      times: (value['times'] as List).cast<double>(),
      xy: (value['xy'] as List).map((v) => (v as List).cast<double>()).toList(),
      flags: (value['flags'] as List)
          .map((v) => (v as List).cast<String>())
          .toList(),
      metadata: value['metadata'] as Map<String, dynamic>,
    ).toJson();
