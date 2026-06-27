/// Identifies a physical wheel. Left and Right are color-coded consistently
/// throughout the app via [WheelSenseColors].
enum WheelSide {
  left('L', 'Left'),
  right('R', 'Right');

  const WheelSide(this.shortLabel, this.label);

  /// Single-character badge label (e.g. "L").
  final String shortLabel;

  /// Human-readable label (e.g. "Left").
  final String label;
}
