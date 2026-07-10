import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/scan/detector_geometry.dart';

void main() {
  group('sortCornerRoles', () {
    test('assigns TL/TR/BR/BL for a shuffled axis-aligned rectangle', () {
      // Rect corners given out of order.
      final pts = <Pt>[
        (x: 100, y: 80), // BR
        (x: 10, y: 5), // TL
        (x: 100, y: 5), // TR
        (x: 10, y: 80), // BL
      ];
      final r = sortCornerRoles(pts);
      expect(r[0], (x: 10.0, y: 5.0), reason: 'TL = smallest x+y');
      expect(r[1], (x: 100.0, y: 5.0), reason: 'TR = smallest y-x');
      expect(r[2], (x: 100.0, y: 80.0), reason: 'BR = largest x+y');
      expect(r[3], (x: 10.0, y: 80.0), reason: 'BL = largest y-x');
    });

    test('assigns roles for a rotated (perspective) quad', () {
      // A trapezoid tilted right: top edge shorter, shifted.
      final pts = <Pt>[
        (x: 30, y: 10), // TL
        (x: 90, y: 20), // TR
        (x: 110, y: 95), // BR
        (x: 15, y: 85), // BL
      ];
      final r = sortCornerRoles(pts);
      expect(r[0], (x: 30.0, y: 10.0));
      expect(r[1], (x: 90.0, y: 20.0));
      expect(r[2], (x: 110.0, y: 95.0));
      expect(r[3], (x: 15.0, y: 85.0));
    });
  });

  group('quadArea', () {
    test('computes rectangle area', () {
      final rect = <Pt>[
        (x: 0, y: 0),
        (x: 100, y: 0),
        (x: 100, y: 50),
        (x: 0, y: 50),
      ];
      expect(quadArea(rect), closeTo(5000, 1e-6));
    });
  });

  group('angleScore', () {
    test('1.0 for a perfect rectangle', () {
      final rect = <Pt>[
        (x: 0, y: 0),
        (x: 100, y: 0),
        (x: 100, y: 50),
        (x: 0, y: 50),
      ];
      expect(angleScore(rect), closeTo(1.0, 1e-9));
    });

    test('lower for a skewed quad', () {
      final skew = <Pt>[
        (x: 0, y: 0),
        (x: 100, y: 0),
        (x: 130, y: 50),
        (x: 0, y: 50),
      ];
      expect(angleScore(skew), lessThan(0.95));
      expect(angleScore(skew), greaterThan(0.0));
    });
  });

  group('rectangularityScore', () {
    test('1.0 when contour fills its quad', () {
      expect(rectangularityScore(5000, 5000), closeTo(1.0, 1e-9));
    });
    test('0.5 for a triangle inside its bounding rect', () {
      expect(rectangularityScore(2500, 5000), closeTo(0.5, 1e-9));
    });
    test('clamps to [0,1] and guards zero quad area', () {
      expect(rectangularityScore(9999, 0), 0.0);
      expect(rectangularityScore(6000, 5000), 1.0);
    });
  });

  group('detectionConfidence', () {
    test('applies the 0.5/0.3/0.2 weighting', () {
      final c = detectionConfidence(
        areaScore: 1.0,
        angleScore: 1.0,
        rectScore: 1.0,
      );
      expect(c, closeTo(1.0, 1e-9));
      final c2 = detectionConfidence(
        areaScore: 0.4,
        angleScore: 1.0,
        rectScore: 0.5,
      );
      expect(c2, closeTo(0.5 * 0.4 + 0.3 * 1.0 + 0.2 * 0.5, 1e-9));
    });
    test('clamps to [0,1]', () {
      expect(
        detectionConfidence(areaScore: 2.0, angleScore: 2.0, rectScore: 2.0),
        1.0,
      );
    });
  });

  group('isPlausiblePage', () {
    test('accepts a mid-frame, well-filled quad', () {
      expect(isPlausiblePage(areaFrac: 0.40, fill: 0.85), isTrue);
      expect(isPlausiblePage(areaFrac: 0.84, fill: 0.78), isTrue);
    });
    test('rejects a near-full-frame blob (blank scene / background)', () {
      expect(isPlausiblePage(areaFrac: 0.97, fill: 0.99), isFalse);
    });
    test('rejects a too-small blob', () {
      expect(isPlausiblePage(areaFrac: 0.03, fill: 0.99), isFalse);
    });
    test('rejects a low-fill blob (clutter / non-rectangular)', () {
      expect(isPlausiblePage(areaFrac: 0.40, fill: 0.50), isFalse);
    });
    test('honors the boundary values (>= and <=)', () {
      expect(isPlausiblePage(areaFrac: 0.05, fill: 0.55), isTrue);
      expect(isPlausiblePage(areaFrac: 0.92, fill: 0.55), isTrue);
      expect(isPlausiblePage(areaFrac: 0.049, fill: 0.99), isFalse);
      expect(isPlausiblePage(areaFrac: 0.40, fill: 0.549), isFalse);
    });
  });

  group('isConvexQuad', () {
    test('accepts an axis-aligned square (CCW and CW windings)', () {
      const ccw = <Pt>[
        (x: 0, y: 0),
        (x: 10, y: 0),
        (x: 10, y: 10),
        (x: 0, y: 10),
      ];
      const cw = <Pt>[
        (x: 0, y: 0),
        (x: 0, y: 10),
        (x: 10, y: 10),
        (x: 10, y: 0),
      ];
      expect(isConvexQuad(ccw), isTrue);
      expect(isConvexQuad(cw), isTrue);
    });

    test('accepts a convex (non-axis-aligned) quad', () {
      const q = <Pt>[(x: 2, y: 0), (x: 12, y: 3), (x: 9, y: 11), (x: 0, y: 8)];
      expect(isConvexQuad(q), isTrue);
    });

    test('rejects a reflex (arrow/dart) quad', () {
      // Third vertex pulled inside → one reflex angle.
      const q = <Pt>[(x: 0, y: 0), (x: 10, y: 0), (x: 5, y: 3), (x: 10, y: 10)];
      expect(isConvexQuad(q), isFalse);
    });

    test('rejects three collinear vertices', () {
      const q = <Pt>[(x: 0, y: 0), (x: 5, y: 0), (x: 10, y: 0), (x: 5, y: 8)];
      expect(isConvexQuad(q), isFalse);
    });

    test('rejects a non-4-point list', () {
      const q = <Pt>[(x: 0, y: 0), (x: 10, y: 0), (x: 10, y: 10)];
      expect(isConvexQuad(q), isFalse);
    });
  });
}
