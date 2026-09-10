/// Identifies a physical wheel. Left and Right are color-coded consistently
/// throughout the app via [WheelAthleteColors].
enum WheelSide {
  left('L', 'Left'),
  right('R', 'Right'),
  center('C', 'Center');

  const WheelSide(this.shortLabel, this.label);

  /// Single-character badge label (e.g. "L").
  final String shortLabel;

  /// Human-readable label (e.g. "Left").
  final String label;

  /// UI label that distinguishes wheel hubs from the chair-frame sensor.
  String get deviceLabel => switch (this) {
    WheelSide.left => 'Left wheel',
    WheelSide.right => 'Right wheel',
    WheelSide.center => 'Chair center',
  };

  bool get isWheelHub => this != WheelSide.center;
}
