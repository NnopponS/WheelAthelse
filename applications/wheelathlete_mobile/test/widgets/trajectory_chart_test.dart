import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/model/trajectory_model.dart';
import 'package:wheelathlete/widgets/trajectory_chart.dart';

void main() {
  test('trajectory bounds always use equal numeric X and Y spans', () {
    final bounds = squareTrajectoryBounds(const [
      TrajectoryPoint(-2, -0.2),
      TrajectoryPoint(8, 0.4),
    ]);
    expect(bounds.xSpan, closeTo(bounds.ySpan, 1e-12));
    expect(bounds.minX, lessThanOrEqualTo(-2));
    expect(bounds.maxX, greaterThanOrEqualTo(8));
    expect(bounds.minY, lessThanOrEqualTo(-0.2));
    expect(bounds.maxY, greaterThanOrEqualTo(0.4));
  });

  test('degenerate trajectory still has a usable square span', () {
    final bounds = squareTrajectoryBounds(const [TrajectoryPoint(1, 2)]);
    expect(bounds.xSpan, closeTo(bounds.ySpan, 1e-12));
    expect(bounds.xSpan, greaterThan(0));
  });
}
