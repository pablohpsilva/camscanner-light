import 'dart:math' as math;

/// A 2-D point in pixel space. Pure-Dart mirror of an OpenCV contour point so
/// the geometry/scoring math is testable without libdartcv (which never loads
/// under host `flutter test`).
typedef Pt = ({double x, double y});

/// Sorts four quad points into canonical corner roles.
/// Returns `[topLeft, topRight, bottomRight, bottomLeft]`.
///  - topLeft     = smallest (x + y)
///  - bottomRight = largest  (x + y)
///  - topRight    = smallest (y - x)
///  - bottomLeft  = largest  (y - x)
List<Pt> sortCornerRoles(List<Pt> pts) {
  assert(pts.length == 4, 'sortCornerRoles expects exactly 4 points');
  final bySum = [...pts]..sort((a, b) => (a.x + a.y).compareTo(b.x + b.y));
  final tl = bySum.first;
  final br = bySum.last;
  final byDiff = [...pts]..sort((a, b) => (a.y - a.x).compareTo(b.y - b.x));
  final tr = byDiff.first;
  final bl = byDiff.last;
  return [tl, tr, br, bl];
}

/// Polygon area via the shoelace formula (absolute value).
double quadArea(List<Pt> quad) {
  double s = 0;
  for (int i = 0; i < quad.length; i++) {
    final a = quad[i];
    final b = quad[(i + 1) % quad.length];
    s += a.x * b.y - b.x * a.y;
  }
  return s.abs() / 2;
}

/// Score in `[0,1]`: how close the four interior angles are to 90°.
/// 1.0 = perfect rectangle; decreases as corners skew.
/// [quad] must be in TL, TR, BR, BL order.
double angleScore(List<Pt> quad) {
  double totalErr = 0;
  for (int i = 0; i < 4; i++) {
    final prev = quad[(i + 3) % 4];
    final curr = quad[i];
    final next = quad[(i + 1) % 4];
    final v1x = prev.x - curr.x, v1y = prev.y - curr.y;
    final v2x = next.x - curr.x, v2y = next.y - curr.y;
    final m1 = math.sqrt(v1x * v1x + v1y * v1y);
    final m2 = math.sqrt(v2x * v2x + v2y * v2y);
    if (m1 < 1e-6 || m2 < 1e-6) continue;
    final cosA = ((v1x * v2x + v1y * v2y) / (m1 * m2)).clamp(-1.0, 1.0);
    totalErr += (math.acos(cosA) * 180 / math.pi - 90).abs();
  }
  return (1.0 - totalErr / (4 * 90)).clamp(0.0, 1.0);
}

/// Score in `[0,1]`: fill ratio of the source contour vs. its enclosing quad.
/// ~1.0 when the contour is itself quadrilateral; low when the quad was
/// synthesized (e.g. `minAreaRect`) around a ragged/non-rectangular blob.
double rectangularityScore(double contourArea, double enclosingArea) {
  if (enclosingArea <= 0) return 0.0;
  return (contourArea / enclosingArea).clamp(0.0, 1.0);
}

/// Weighted detection confidence in `[0,1]`.
double detectionConfidence({
  required double areaScore,
  required double angleScore,
  required double rectScore,
}) =>
    (0.5 * areaScore + 0.3 * angleScore + 0.2 * rectScore).clamp(0.0, 1.0);

/// Accept predicate for a candidate page quad. Rejects the near-full-frame
/// blob of a blank scene (or the background polarity), a too-small blob, and a
/// low-fill (non-rectangular) clutter blob. A legitimate page can fill most of
/// the frame and touch all borders, so border-touching is deliberately NOT a
/// criterion — the area cap and fill floor already exclude the background/blank
/// blobs.
bool isPlausiblePage({
  required double areaFrac,
  required double fill,
  double minAreaFrac = 0.05,
  double maxAreaFrac = 0.92,
  double minFill = 0.55,
}) =>
    areaFrac >= minAreaFrac && areaFrac <= maxAreaFrac && fill >= minFill;
