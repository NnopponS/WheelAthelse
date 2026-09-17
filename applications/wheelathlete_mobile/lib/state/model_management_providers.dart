import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wheelathlete/model/kinematic_trajectory_model.dart';
import 'package:wheelathlete/model/model_spec.dart';
import 'package:wheelathlete/model/on_device_trajectory_model.dart';
import 'package:wheelathlete/model/three_imu_trajectory_model.dart';
import 'package:wheelathlete/model/trajectory_model.dart';
import 'package:wheelathlete/records/session_model.dart';
import 'package:wheelathlete/state/ble_providers.dart';

/// Available trajectory models for WheelAthlete mobile.
///
/// Mirrors the Python Research Edition's model discovery:
/// 1. 3IMU v4 Kinematic (L/R/C) [Active - 3-IMU generic enhanced odometry]
/// 2. Kinematic Trajectory (XY + Yaw) [Supported - dual-hub kinematic baseline]
/// 3. BiWheel3D M4 - On-device [Legacy Experimental - deep ONNX (TCN + BiLSTM)]
final availableModelsProvider = Provider<List<ModelSpec>>((ref) {
  return const [
    ModelSpec(
      key: threeImuV4ModelKey,
      label: threeImuV4ModelLabel,
      description:
          'Three-IMU L/R/C wheelchair odometry v4 with variance-guarded '
          'stillness detection, zero-rate bias correction, and center-wheel yaw fusion.',
      kind: 'three_imu_v4',
      modelVersion: '4.0',
      requiredSensorRoles: ['L', 'R', 'C'],
      outputCapabilities: [
        'x_m',
        'y_m',
        'signed_speed_mps',
        'yaw_rad',
        'yaw_rate_radps',
      ],
      isBundled: true,
      isExperimental: false,
    ),
    ModelSpec(
      key: kinematicModelKey,
      label: 'Kinematic Trajectory (XY + Yaw)',
      description:
          'Dual-hub kinematic trajectory estimator (XY + Yaw). '
          'Fast, deterministic on-device odometry with chassis yaw calibration.',
      kind: 'recipe',
      modelVersion: '1.0',
      requiredSensorRoles: ['L', 'R'],
      outputCapabilities: [
        'x_m',
        'y_m',
        'signed_speed_mps',
        'yaw_rad',
        'yaw_rate_radps',
      ],
      isBundled: true,
      assetPath: 'assets/models/BiWheel3D-XY-Yaw-current_best.json',
    ),
    ModelSpec(
      key: 'biwheel3d:m4_onnx',
      label: 'BiWheel3D M4 (TCN + BiLSTM ONNX)',
      description:
          'Legacy experimental deep temporal convolutional + bidirectional LSTM network. '
          'Runs on CPU using ONNX Runtime with 90-dimensional feature extraction.',
      kind: 'onnx',
      modelVersion: 'M4',
      requiredSensorRoles: ['L', 'R'],
      outputCapabilities: ['x_m', 'y_m'],
      isBundled: true,
      isExperimental: true,
      assetPath: biwheel3dMobileModelAsset,
    ),
  ];
});

/// Notifier for currently selected model key.
class SelectedModelKeyNotifier extends Notifier<String> {
  @override
  String build() => kinematicModelKey;

  void set(String key) => state = key;
}

final selectedModelKeyProvider =
    NotifierProvider<SelectedModelKeyNotifier, String>(
  SelectedModelKeyNotifier.new,
);

/// Currently active ModelSpec instance.
final activeModelSpecProvider = Provider<ModelSpec>((ref) {
  final key = ref.watch(selectedModelKeyProvider);
  final models = ref.watch(availableModelsProvider);
  return models.firstWhere((m) => m.key == key, orElse: () => models.first);
});

/// Notifier for currently selected session ID for model evaluation.
class SelectedModelSessionIdNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? sessionId) => state = sessionId;
}

final selectedModelSessionIdProvider =
    NotifierProvider<SelectedModelSessionIdNotifier, String?>(
  SelectedModelSessionIdNotifier.new,
);

/// State of the model inference runner.
class ModelInferenceState {
  const ModelInferenceState({
    this.isRunning = false,
    this.result,
    this.error,
    this.sessionMeta,
    this.statusMessage = 'Select a session and model to generate a trajectory',
  });

  final bool isRunning;
  final TrajectoryResult? result;
  final String? error;
  final SessionMeta? sessionMeta;
  final String statusMessage;

  ModelInferenceState copyWith({
    bool? isRunning,
    TrajectoryResult? result,
    String? error,
    SessionMeta? sessionMeta,
    String? statusMessage,
  }) => ModelInferenceState(
    isRunning: isRunning ?? this.isRunning,
    result: result ?? this.result,
    error: error,
    sessionMeta: sessionMeta ?? this.sessionMeta,
    statusMessage: statusMessage ?? this.statusMessage,
  );
}

class ModelInferenceNotifier extends Notifier<ModelInferenceState> {
  OnDeviceTrajectoryModelClient? _onnxClient;
  KinematicTrajectoryModelClient? _kinematicClient;
  ThreeImuTrajectoryModelClient? _threeImuClient;

  @override
  ModelInferenceState build() {
    ref.onDispose(() {
      _onnxClient?.dispose();
    });
    return const ModelInferenceState();
  }

  TrajectoryModelClient _getClientForSpec(ModelSpec spec) {
    if (spec.kind == 'three_imu_v4' || spec.key == threeImuV4ModelKey) {
      return _threeImuClient ??= const ThreeImuTrajectoryModelClient();
    }
    if (spec.kind == 'onnx') {
      return _onnxClient ??= OnDeviceTrajectoryModelClient();
    }
    return _kinematicClient ??= const KinematicTrajectoryModelClient();
  }

  Future<void> runInference({
    required SessionMeta meta,
    required List<BufferedSample> samples,
  }) async {
    final spec = ref.read(activeModelSpecProvider);
    state = state.copyWith(
      isRunning: true,
      error: null,
      sessionMeta: meta,
      statusMessage: 'Preparing session samples for ${spec.label}…',
    );

    try {
      final client = _getClientForSpec(spec);
      final TrajectoryResult result;

      if (spec.key == threeImuV4ModelKey || spec.requiredSensorRoles.contains('C')) {
        state = state.copyWith(
          statusMessage: 'Running ${spec.label} on 3-IMU synchronized streams…',
        );
        final threeClient = client as ThreeImuTrajectoryModelClient;
        result = await threeClient.inferFromSamples(meta: meta, samples: samples);
      } else {
        final input = prepareTrajectoryInput(
          samples,
          sourceRateHz: meta.sampleRateHz,
          meta: meta,
        );
        state = state.copyWith(
          statusMessage: 'Running ${spec.label} on ${input.modelStepCount} steps…',
        );
        result = await client.infer(meta: meta, input: input);
      }

      state = state.copyWith(
        isRunning: false,
        result: result,
        error: null,
        statusMessage:
            'Generated ${result.points.length} trajectory points (${result.pathLengthM.toStringAsFixed(1)} m)',
      );
    } on Object catch (e) {
      state = state.copyWith(
        isRunning: false,
        error: '$e',
        statusMessage: 'Inference failed: $e',
      );
    }
  }

  Future<void> runOnSessionId(String sessionId) async {
    final storage = ref.read(storageRepositoryProvider);
    final allSessions = await storage.listAllSessions();
    final meta = allSessions.where((s) => s.sessionId == sessionId).firstOrNull;
    if (meta == null) {
      state = state.copyWith(error: 'Session $sessionId not found.');
      return;
    }

    final csvSamples = await storage.readSamples(
      meta.topic,
      meta.trialNumber,
      meta.sessionId,
    );
    await runInference(meta: meta, samples: csvSamples);
  }

  void clearResult() {
    state = const ModelInferenceState();
  }
}

final modelInferenceProvider =
    NotifierProvider<ModelInferenceNotifier, ModelInferenceState>(
      ModelInferenceNotifier.new,
    );
