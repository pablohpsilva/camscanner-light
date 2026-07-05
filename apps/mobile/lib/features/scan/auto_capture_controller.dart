import 'dart:math' as math;

import '../library/crop_corners.dart';
import 'edge_detector.dart';

/// Progress toward an automatic capture, emitted once per frame by
/// [AutoCaptureController].
class AutoCaptureState {
  /// Fraction of the required stable dwell accumulated so far, in `[0,1]`.
  final double progress;

  /// True on the frame the dwell is first satisfied. The caller should fire the
  /// shutter and then call [AutoCaptureController.reset].
  final bool shouldFire;

  const AutoCaptureState({required this.progress, required this.shouldFire});
}

/// Tracks whether a live-detected document quad is being held steady, so the
/// scan screen can auto-fire the shutter. Pure and frame-driven (no clock): the
/// live sampling throttle floors the wall-time of [requiredStableFrames].
class AutoCaptureController {
  /// Consecutive stable, confident frames required to fire.
  final int requiredStableFrames;

  /// Max per-corner displacement (normalized `[0..1]` coords) between two frames
  /// still counted as "stable".
  final double maxCornerDelta;

  /// Minimum detection confidence for a frame to count toward stability.
  final double minConfidence;

  AutoCaptureController({
    this.requiredStableFrames = 6,
    this.maxCornerDelta = 0.02,
    this.minConfidence = 0.6,
  });

  CropCorners? _last;
  int _count = 0;
  bool _fired = false;

  /// Feeds one detection [result] (null = no document this frame). Returns the
  /// updated progress and whether the dwell is now satisfied.
  AutoCaptureState update(DetectionResult? result) {
    if (result == null || result.confidence < minConfidence) {
      reset();
      return const AutoCaptureState(progress: 0, shouldFire: false);
    }
    final corners = result.corners;
    if (_last != null && _maxDelta(_last!, corners) > maxCornerDelta) {
      _count = 1; // moved too much — this frame is the new baseline
    } else if (_count < requiredStableFrames) {
      _count += 1;
    }
    _last = corners;
    final fire = _count >= requiredStableFrames && !_fired;
    if (fire) _fired = true;
    return AutoCaptureState(
      progress: (_count / requiredStableFrames).clamp(0.0, 1.0),
      shouldFire: fire,
    );
  }

  /// Clears accumulated stability (call after firing, or when sampling stops).
  void reset() {
    _last = null;
    _count = 0;
    _fired = false;
  }

  static double _maxDelta(CropCorners a, CropCorners b) => [
        (a.topLeft - b.topLeft).distance,
        (a.topRight - b.topRight).distance,
        (a.bottomRight - b.bottomRight).distance,
        (a.bottomLeft - b.bottomLeft).distance,
      ].reduce(math.max);
}
