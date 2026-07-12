import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/crop_corners.dart';

// Corners are computed via `1 - coord`, so exact float equality is unsafe
// (e.g. 1 - 0.9 != 0.1 at the bit level). Compare within a tight tolerance.
void expectOffsetClose(Offset a, Offset b, [double tol = 1e-9]) {
  expect(a.dx, closeTo(b.dx, tol));
  expect(a.dy, closeTo(b.dy, tol));
}

void main() {
  test('fullFrame is invariant under rotate90Cw', () {
    expect(CropCorners.fullFrame.rotate90Cw(), CropCorners.fullFrame);
  });

  test('four quarter-turns return the same quad (identity)', () {
    const c = CropCorners(
      topLeft: Offset(0.1, 0.2),
      topRight: Offset(0.8, 0.2),
      bottomRight: Offset(0.8, 0.9),
      bottomLeft: Offset(0.1, 0.9),
    );
    final r = c.rotate90Cw().rotate90Cw().rotate90Cw().rotate90Cw();
    expectOffsetClose(r.topLeft, c.topLeft);
    expectOffsetClose(r.topRight, c.topRight);
    expectOffsetClose(r.bottomRight, c.bottomRight);
    expectOffsetClose(r.bottomLeft, c.bottomLeft);
  });

  test('rotates a known quad CW (point map + role remap)', () {
    const c = CropCorners(
      topLeft: Offset(0.1, 0.2),
      topRight: Offset(0.8, 0.2),
      bottomRight: Offset(0.8, 0.9),
      bottomLeft: Offset(0.1, 0.9),
    );
    final r = c.rotate90Cw();
    expectOffsetClose(r.topLeft, const Offset(0.1, 0.1));
    expectOffsetClose(r.topRight, const Offset(0.8, 0.1));
    expectOffsetClose(r.bottomRight, const Offset(0.8, 0.8));
    expectOffsetClose(r.bottomLeft, const Offset(0.1, 0.8));
  });

  test('rotates mid-edge deviations with their edges', () {
    const c = CropCorners(
      topLeft: Offset(0.0, 0.0),
      topRight: Offset(1.0, 0.0),
      bottomRight: Offset(1.0, 1.0),
      bottomLeft: Offset(0.0, 1.0),
      topMidDev: Offset(0.0, -0.05), // top edge bulges up
    );
    final r = c.rotate90Cw();
    // old top edge becomes the new RIGHT edge; vector (0,-0.05) -> (0.05, 0)
    expect(r.rightMidDev.dx, closeTo(0.05, 1e-9));
    expect(r.rightMidDev.dy, closeTo(0.0, 1e-9));
    expect(r.topMidDev, Offset.zero);
  });
}
