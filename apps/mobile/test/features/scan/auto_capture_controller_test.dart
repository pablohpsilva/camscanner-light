import 'dart:ui' show Offset;
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/scan/auto_capture_controller.dart';
import 'package:mobile/features/scan/edge_detector.dart';

DetectionResult _res(CropCorners c, double conf) =>
    DetectionResult(corners: c, confidence: conf);

/// A unit-square-ish quad translated by (dx, dy).
CropCorners _quad(double dx, double dy) => CropCorners(
      topLeft: Offset(0.1 + dx, 0.1 + dy),
      topRight: Offset(0.9 + dx, 0.1 + dy),
      bottomRight: Offset(0.9 + dx, 0.9 + dy),
      bottomLeft: Offset(0.1 + dx, 0.9 + dy),
    );

void main() {
  test('null result keeps progress 0 and never fires', () {
    final s = AutoCaptureController().update(null);
    expect(s.progress, 0);
    expect(s.shouldFire, isFalse);
  });

  test('below-minConfidence result resets progress', () {
    final c = AutoCaptureController(requiredStableFrames: 3);
    c.update(_res(_quad(0, 0), 0.9)); // count 1
    final s = c.update(_res(_quad(0, 0), 0.4)); // low conf -> reset
    expect(s.progress, 0);
    expect(s.shouldFire, isFalse);
  });

  test('N stable confident frames fire on the Nth, progress climbs to 1', () {
    final c = AutoCaptureController(requiredStableFrames: 3);
    expect(c.update(_res(_quad(0, 0), 0.9)).progress, closeTo(1 / 3, 1e-9));
    expect(c.update(_res(_quad(0, 0), 0.9)).progress, closeTo(2 / 3, 1e-9));
    final third = c.update(_res(_quad(0, 0), 0.9));
    expect(third.progress, 1.0);
    expect(third.shouldFire, isTrue);
  });

  test('a jump larger than maxCornerDelta restarts the count', () {
    final c = AutoCaptureController(requiredStableFrames: 3, maxCornerDelta: 0.02);
    c.update(_res(_quad(0, 0), 0.9)); // count 1
    c.update(_res(_quad(0, 0), 0.9)); // count 2
    final moved = c.update(_res(_quad(0.2, 0), 0.9)); // big jump -> count 1
    expect(moved.progress, closeTo(1 / 3, 1e-9));
    expect(moved.shouldFire, isFalse);
  });

  test('displacement at the threshold boundary counts as stable', () {
    final c =
        AutoCaptureController(requiredStableFrames: 2, maxCornerDelta: 0.25);
    // Base coords and the 0.25 shift are exactly representable in binary FP,
    // so each corner moves exactly 0.25 == maxCornerDelta (boundary, still stable).
    CropCorners q(double dx) => CropCorners(
          topLeft: Offset(0.25 + dx, 0.25),
          topRight: Offset(0.5 + dx, 0.25),
          bottomRight: Offset(0.5 + dx, 0.5),
          bottomLeft: Offset(0.25 + dx, 0.5),
        );
    c.update(_res(q(0), 0.9)); // count 1
    final s = c.update(_res(q(0.25), 0.9));
    expect(s.progress, 1.0);
    expect(s.shouldFire, isTrue);
  });

  test('fires once; re-arms after losing the doc or reset()', () {
    final c = AutoCaptureController(requiredStableFrames: 2);
    c.update(_res(_quad(0, 0), 0.9)); // count 1
    expect(c.update(_res(_quad(0, 0), 0.9)).shouldFire, isTrue); // fires
    expect(c.update(_res(_quad(0, 0), 0.9)).shouldFire, isFalse); // no re-fire
    c.update(null); // lose the doc -> internal reset
    c.update(_res(_quad(0, 0), 0.9)); // count 1
    expect(c.update(_res(_quad(0, 0), 0.9)).shouldFire, isTrue); // fires again
  });

  test('reset() clears accumulated progress', () {
    final c = AutoCaptureController(requiredStableFrames: 3);
    c.update(_res(_quad(0, 0), 0.9));
    c.update(_res(_quad(0, 0), 0.9));
    c.reset();
    expect(c.update(_res(_quad(0, 0), 0.9)).progress, closeTo(1 / 3, 1e-9));
  });
}
