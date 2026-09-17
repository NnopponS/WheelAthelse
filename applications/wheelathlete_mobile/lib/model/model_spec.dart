import 'package:flutter/foundation.dart';

/// Specification and metadata describing a trajectory model runtime in WheelAthlete.
///
/// Mirrors the contract in the Python Research Edition (`ModelSpec`).
@immutable
class ModelSpec {
  const ModelSpec({
    required this.key,
    required this.label,
    required this.description,
    required this.kind,
    this.modelVersion = '1',
    this.requiredSensorRoles = const ['L', 'R'],
    this.outputCapabilities = const [
      'x_m',
      'y_m',
      'signed_speed_mps',
      'yaw_rad',
      'yaw_rate_radps',
    ],
    this.isBundled = true,
    this.isExperimental = false,
    this.assetPath,
  });

  /// Unique canonical model key.
  final String key;

  /// Short display label for UI dropdowns and badges.
  final String label;

  /// Detailed human-readable description of architecture and physics.
  final String description;

  /// Model kind: 'recipe' (kinematic integration) or 'onnx' (neural network graph).
  final String kind;

  /// Model version string.
  final String modelVersion;

  /// Required physical sensor roles ('L', 'R', and optionally 'C').
  final List<String> requiredSensorRoles;

  /// Names of physical outputs produced by this model.
  final List<String> outputCapabilities;

  /// Whether this model is bundled within the application package.
  final bool isBundled;

  /// Whether this model is considered experimental.
  final bool isExperimental;

  /// Asset bundle path if packaged with the app.
  final String? assetPath;

  bool get hasYaw => outputCapabilities.contains('yaw_rad');
  bool get hasSpeed => outputCapabilities.contains('signed_speed_mps');

  String get technicalSummary =>
      '${isExperimental ? 'Experimental' : 'Supported'} · '
      '$kind · version $modelVersion · '
      'inputs ${requiredSensorRoles.join('/')} · '
      'outputs ${outputCapabilities.join(', ')}';
}
