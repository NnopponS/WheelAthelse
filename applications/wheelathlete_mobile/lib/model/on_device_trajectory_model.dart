import 'package:flutter/services.dart';
import 'package:onnxruntime_v2/onnxruntime_v2.dart';
import 'package:wheelathlete/model/trajectory_model.dart';
import 'package:wheelathlete/records/session_model.dart';

const String biwheel3dMobileModelAsset =
    'assets/models/wheelathlete_biwheel3d_m4.onnx';
const String biwheel3dMobileModelLabel = 'BiWheel3D M4 - On-device';

/// Runs the validated BiWheel3D M4 graph entirely on the phone.
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

  @override
  Future<TrajectoryResult> infer({
    required SessionMeta meta,
    required TrajectoryPreprocessResult input,
  }) async {
    if (_disposed) {
      throw const TrajectoryModelException(
        'The on-device trajectory model has already been disposed.',
      );
    }
    final steps = input.modelStepCount;
    final features = extractBiwheel3dFeatures(input);
    if (features.length != steps * biwheel3dFeatureDim) {
      throw const TrajectoryModelException(
        'BiWheel3D feature tensor has an unexpected size.',
      );
    }

    final session = await (_sessionFuture ??= _loadSession());
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
      return TrajectoryResult(
        points: aligned,
        modelLabel: biwheel3dMobileModelLabel,
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
