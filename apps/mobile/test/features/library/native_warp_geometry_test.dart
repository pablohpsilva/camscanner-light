import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/library/native_warp_geometry.dart';

void main() {
  group('nativeWarpOutputSize', () {
    test('straight full-frame crop under cap keeps source dimensions', () {
      final size = nativeWarpOutputSize(CropCorners.fullFrame, 1000, 800, 3500);
      expect(size, (1000, 800));
    });

    test('pxW takes the longer of the two opposite horizontal edges', () {
      // Top edge is longer than the bottom edge: topRight pushed beyond the
      // right border while the bottom edge stays the full width. With w=1000,
      // h=800: top edge dx=(1.2-0)*1000=1200; bottom edge dx=1000. pxW=max=1200.
      const crop = CropCorners(
        topLeft: Offset(0, 0),
        topRight: Offset(1.2, 0),
        bottomRight: Offset(1, 1),
        bottomLeft: Offset(0, 1),
      );
      final (pxW, pxH) = nativeWarpOutputSize(crop, 1000, 800, 3500);
      expect(pxW, 1200);
      // Left edge dy=(1-0)*800=800; right edge dx=(1.2-1)*1000=200,
      // dy=800 -> sqrt(200^2+800^2)=~824.6 -> round 825. pxH=max(800,825)=825.
      expect(pxH, 825);
    });

    test('degenerate near-zero crop clamps to at least 2 x 2', () {
      const crop = CropCorners(
        topLeft: Offset(0, 0),
        topRight: Offset(0.0001, 0),
        bottomRight: Offset(0.0001, 0.0001),
        bottomLeft: Offset(0, 0.0001),
      );
      final (pxW, pxH) = nativeWarpOutputSize(crop, 1000, 800, 3500);
      expect(pxW, greaterThanOrEqualTo(2));
      expect(pxH, greaterThanOrEqualTo(2));
    });

    test(
      'longest side is clamped to cap and the other scaled proportionally',
      () {
        // fullFrame at w=8000,h=6000: pxW=8000, pxH=6000. longest 8000>3500.
        // s=3500/8000=0.4375. pxW=(8000*0.4375).round()=3500;
        // pxH=(6000*0.4375).round()=2625.
        final size = nativeWarpOutputSize(
          CropCorners.fullFrame,
          8000,
          6000,
          3500,
        );
        expect(size, (3500, 2625));
      },
    );
  });
}
