import 'package:flutter/painting.dart';

/// Four crop corners of one page, normalized to `[0..1]` in the DISPLAY
/// (EXIF-applied) frame, top-left origin. Role-tagged (not a list): dragging
/// never reassigns which corner is which. Persisted as page metadata (E1);
/// E2 perspective-flattens from these; E3 re-edits. Pure — no widgets.
class CropCorners {
  final Offset topLeft, topRight, bottomRight, bottomLeft;
  final Offset topMidDev, rightMidDev, bottomMidDev, leftMidDev;
  const CropCorners({
    required this.topLeft,
    required this.topRight,
    required this.bottomRight,
    required this.bottomLeft,
    this.topMidDev = Offset.zero,
    this.rightMidDev = Offset.zero,
    this.bottomMidDev = Offset.zero,
    this.leftMidDev = Offset.zero,
  });

  /// The whole image, uncropped — the default and the meaning of a null/legacy
  /// stored value.
  static const CropCorners fullFrame = CropCorners(
    topLeft: Offset(0, 0),
    topRight: Offset(1, 0),
    bottomRight: Offset(1, 1),
    bottomLeft: Offset(0, 1),
  );

  static Offset _mid(Offset a, Offset b) =>
      Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);

  Offset get topCenter => _mid(topLeft, topRight);
  Offset get rightCenter => _mid(topRight, bottomRight);
  Offset get bottomCenter => _mid(bottomRight, bottomLeft);
  Offset get leftCenter => _mid(bottomLeft, topLeft);

  Offset get topMid => topCenter + topMidDev;
  Offset get rightMid => rightCenter + rightMidDev;
  Offset get bottomMid => bottomCenter + bottomMidDev;
  Offset get leftMid => leftCenter + leftMidDev;

  static const double _straightEps = 1e-9;
  bool get isStraight =>
      topMidDev.distanceSquared < _straightEps &&
      rightMidDev.distanceSquared < _straightEps &&
      bottomMidDev.distanceSquared < _straightEps &&
      leftMidDev.distanceSquared < _straightEps;

  CropCorners copyWith({
    Offset? topLeft,
    Offset? topRight,
    Offset? bottomRight,
    Offset? bottomLeft,
    Offset? topMidDev,
    Offset? rightMidDev,
    Offset? bottomMidDev,
    Offset? leftMidDev,
  }) => CropCorners(
    topLeft: topLeft ?? this.topLeft,
    topRight: topRight ?? this.topRight,
    bottomRight: bottomRight ?? this.bottomRight,
    bottomLeft: bottomLeft ?? this.bottomLeft,
    topMidDev: topMidDev ?? this.topMidDev,
    rightMidDev: rightMidDev ?? this.rightMidDev,
    bottomMidDev: bottomMidDev ?? this.bottomMidDev,
    leftMidDev: leftMidDev ?? this.leftMidDev,
  );

  /// Clamps corners to `[0,1]`, then pulls each resolved midpoint into `[0,1]`
  /// by adjusting its deviation.
  CropCorners clamp() {
    final tl = _clamp(topLeft), tr = _clamp(topRight);
    final br = _clamp(bottomRight), bl = _clamp(bottomLeft);
    Offset dev(Offset a, Offset b, Offset d) =>
        _clamp(_mid(a, b) + d) - _mid(a, b);
    return CropCorners(
      topLeft: tl,
      topRight: tr,
      bottomRight: br,
      bottomLeft: bl,
      topMidDev: dev(tl, tr, topMidDev),
      rightMidDev: dev(tr, br, rightMidDev),
      bottomMidDev: dev(br, bl, bottomMidDev),
      leftMidDev: dev(bl, tl, leftMidDev),
    );
  }

  /// `"x0,y0,x1,y1,x2,y2,x3,y3,devX0,devY0,devX1,devY1,devX2,devY2,devX3,devY3"`
  /// in role order TL,TR,BR,BL,topDev,rightDev,bottomDev,leftDev, fixed precision.
  String toStorage() => [
    topLeft.dx,
    topLeft.dy,
    topRight.dx,
    topRight.dy,
    bottomRight.dx,
    bottomRight.dy,
    bottomLeft.dx,
    bottomLeft.dy,
    topMidDev.dx,
    topMidDev.dy,
    rightMidDev.dx,
    rightMidDev.dy,
    bottomMidDev.dx,
    bottomMidDev.dy,
    leftMidDev.dx,
    leftMidDev.dy,
  ].map((d) => d.toStringAsFixed(6)).join(',');

  /// Fail-soft: returns null on null / empty / wrong count / non-numeric /
  /// non-finite (NaN/Infinity). NEVER throws — a bad stored value must not
  /// brick the list or viewer.
  static CropCorners? tryParse(String? s) {
    if (s == null || s.isEmpty) return null;
    final parts = s.split(',');
    if (parts.length != 8 && parts.length != 16) return null;
    final v = <double>[];
    for (final p in parts) {
      final d = double.tryParse(p);
      if (d == null || !d.isFinite) return null;
      v.add(d);
    }
    final corners = CropCorners(
      topLeft: Offset(v[0], v[1]),
      topRight: Offset(v[2], v[3]),
      bottomRight: Offset(v[4], v[5]),
      bottomLeft: Offset(v[6], v[7]),
    );
    if (parts.length == 8) return corners;
    return corners.copyWith(
      topMidDev: Offset(v[8], v[9]),
      rightMidDev: Offset(v[10], v[11]),
      bottomMidDev: Offset(v[12], v[13]),
      leftMidDev: Offset(v[14], v[15]),
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
      other.bottomLeft == bottomLeft &&
      other.topMidDev == topMidDev &&
      other.rightMidDev == rightMidDev &&
      other.bottomMidDev == bottomMidDev &&
      other.leftMidDev == leftMidDev;

  @override
  int get hashCode => Object.hash(
    topLeft,
    topRight,
    bottomRight,
    bottomLeft,
    topMidDev,
    rightMidDev,
    bottomMidDev,
    leftMidDev,
  );

  @override
  String toString() =>
      'CropCorners($topLeft, $topRight, $bottomRight, $bottomLeft; '
      'devs $topMidDev,$rightMidDev,$bottomMidDev,$leftMidDev)';
}
