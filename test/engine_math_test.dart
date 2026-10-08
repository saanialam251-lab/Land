import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:measure_reality/measure/sensor_engine.dart';

void main() {
  group('floor distance maths  d = h / tan(a)', () {
    final engine = SensorEngine();

    test('45 degrees down: distance equals the phone height', () {
      final d = engine.floorDistance(1.4, pose: const Pose(math.pi / 4, 0, 0));
      expect(d, isNotNull);
      expect(d!, closeTo(1.4, 1e-9));
    });

    test('30 degrees down: d = h / tan(30)', () {
      final d = engine.floorDistance(1.5, pose: Pose(30 * math.pi / 180, 0, 0));
      expect(d!, closeTo(1.5 / math.tan(30 * math.pi / 180), 1e-9));
    });

    test('aimed at the horizon: no floor point', () {
      expect(engine.floorDistance(1.4, pose: Pose(1 * math.pi / 180, 0, 0)), isNull);
    });

    test('turning 90 degrees moves the point to the east', () {
      final p = engine.floorPoint(1.4, pose: const Pose(math.pi / 4, 0, math.pi / 2));
      expect(p, isNotNull);
      expect(p!.e, closeTo(1.4, 1e-9));
      expect(p.n, closeTo(0, 1e-9));
      expect(p.u, closeTo(-1.4, 1e-9));
    });

    test('with no readings yet the steady pose is the live pose', () {
      final e = SensorEngine()..pitchDown = 0.5;
      expect(e.stablePose().pitchDown, closeTo(0.5, 1e-12));
    });
  });

  group('error model', () {
    test('typical single point at 3 m with a 1.4 m phone height', () {
      expect(MeasureError.pointSigma(3, 1.4), closeTo(0.0695, 0.002));
    });

    test('farther points are less precise', () {
      final near = MeasureError.pointSigma(1.5, 1.4);
      final mid = MeasureError.pointSigma(3, 1.4);
      final far = MeasureError.pointSigma(6, 1.4);
      expect(mid, greaterThan(near));
      expect(far, greaterThan(mid));
    });

    test('segment error is larger than a single point error', () {
      const a = WorldPoint(0, -1.4, 2);
      const b = WorldPoint(1, -1.4, 3);
      expect(MeasureError.segmentSigma(a, b, 1.4), greaterThan(MeasureError.pointSigma(2, 1.4)));
    });
  });
}
