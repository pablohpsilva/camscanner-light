import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/crop_corners.dart';

void main() {
  test('fullFrame is the unit square in role order', () {
    expect(CropCorners.fullFrame.topLeft, const Offset(0, 0));
    expect(CropCorners.fullFrame.topRight, const Offset(1, 0));
    expect(CropCorners.fullFrame.bottomRight, const Offset(1, 1));
    expect(CropCorners.fullFrame.bottomLeft, const Offset(0, 1));
  });

  test('clamp pulls every corner into [0,1]x[0,1]', () {
    const c = CropCorners(
      topLeft: Offset(-0.2, -0.5), topRight: Offset(1.3, 0.1),
      bottomRight: Offset(2.0, 1.4), bottomLeft: Offset(-1.0, 0.9));
    final r = c.clamp();
    expect(r.topLeft, const Offset(0, 0));
    expect(r.topRight, const Offset(1, 0.1));
    expect(r.bottomRight, const Offset(1, 1));
    expect(r.bottomLeft, const Offset(0, 0.9));
  });

  test('toStorage <-> tryParse round-trips in role order', () {
    const c = CropCorners(
      topLeft: Offset(0.1, 0.2), topRight: Offset(0.9, 0.15),
      bottomRight: Offset(0.85, 0.95), bottomLeft: Offset(0.05, 0.9));
    final parsed = CropCorners.tryParse(c.toStorage());
    expect(parsed, c);
  });

  test('tryParse is fail-soft on bad input (never throws)', () {
    expect(CropCorners.tryParse(null), isNull);
    expect(CropCorners.tryParse(''), isNull);
    expect(CropCorners.tryParse('0.1,0.2,0.3'), isNull);            // wrong count
    expect(CropCorners.tryParse('a,b,c,d,e,f,g,h'), isNull);        // non-numeric
    expect(CropCorners.tryParse('0,0,1,0,1,1,0,NaN'), isNull);      // NaN token
    expect(CropCorners.tryParse('0,0,1,0,1,1,0,Infinity'), isNull); // inf token
  });

  test('value equality', () {
    expect(CropCorners.fullFrame, CropCorners.fullFrame);
    expect(
      const CropCorners(topLeft: Offset(0, 0), topRight: Offset(1, 0),
          bottomRight: Offset(1, 1), bottomLeft: Offset(0, 1)),
      CropCorners.fullFrame,
    );
    expect(
      const CropCorners(topLeft: Offset(0.5, 0), topRight: Offset(1, 0),
          bottomRight: Offset(1, 1), bottomLeft: Offset(0, 1)),
      isNot(CropCorners.fullFrame),
    );
  });
}
