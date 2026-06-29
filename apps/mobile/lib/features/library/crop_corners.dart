import 'package:flutter/painting.dart';

/// Four crop corners of one page, normalized to `[0..1]` in the DISPLAY
/// (EXIF-applied) frame, top-left origin. Role-tagged (not a list): dragging
/// never reassigns which corner is which. Persisted as page metadata (E1);
/// E2 perspective-flattens from these; E3 re-edits. Pure — no widgets.
class CropCorners {
  final Offset topLeft, topRight, bottomRight, bottomLeft;
  const CropCorners({
    required this.topLeft,
    required this.topRight,
    required this.bottomRight,
    required this.bottomLeft,
  });

  /// The whole image, uncropped — the default and the meaning of a null/legacy
  /// stored value.
  static const CropCorners fullFrame = CropCorners(
    topLeft: Offset(0, 0),
    topRight: Offset(1, 0),
    bottomRight: Offset(1, 1),
    bottomLeft: Offset(0, 1),
  );

  /// Each corner pulled into `[0,1]x[0,1]`.
  CropCorners clamp() => CropCorners(
        topLeft: _clamp(topLeft),
        topRight: _clamp(topRight),
        bottomRight: _clamp(bottomRight),
        bottomLeft: _clamp(bottomLeft),
      );

  /// `"x0,y0,x1,y1,x2,y2,x3,y3"` in role order TL,TR,BR,BL, fixed precision.
  String toStorage() => [
        topLeft.dx, topLeft.dy,
        topRight.dx, topRight.dy,
        bottomRight.dx, bottomRight.dy,
        bottomLeft.dx, bottomLeft.dy,
      ].map((d) => d.toStringAsFixed(6)).join(',');

  /// Fail-soft: returns null on null / empty / wrong count / non-numeric /
  /// non-finite (NaN/Infinity). NEVER throws — a bad stored value must not
  /// brick the list or viewer.
  static CropCorners? tryParse(String? s) {
    if (s == null || s.isEmpty) return null;
    final parts = s.split(',');
    if (parts.length != 8) return null;
    final v = <double>[];
    for (final p in parts) {
      final d = double.tryParse(p);
      if (d == null || !d.isFinite) return null;
      v.add(d);
    }
    return CropCorners(
      topLeft: Offset(v[0], v[1]),
      topRight: Offset(v[2], v[3]),
      bottomRight: Offset(v[4], v[5]),
      bottomLeft: Offset(v[6], v[7]),
    );
  }

  static Offset _clamp(Offset o) =>
      Offset(o.dx.clamp(0.0, 1.0), o.dy.clamp(0.0, 1.0));

  @override
  bool operator ==(Object other) =>
      other is CropCorners &&
      other.topLeft == topLeft &&
      other.topRight == topRight &&
      other.bottomRight == bottomRight &&
      other.bottomLeft == bottomLeft;

  @override
  int get hashCode => Object.hash(topLeft, topRight, bottomRight, bottomLeft);

  @override
  String toString() => 'CropCorners($topLeft, $topRight, $bottomRight, $bottomLeft)';
}
