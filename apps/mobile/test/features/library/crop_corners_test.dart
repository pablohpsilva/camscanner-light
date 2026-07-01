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

  group('deviation model', () {
    const bent = CropCorners(
      topLeft: Offset(0, 0), topRight: Offset(1, 0),
      bottomRight: Offset(1, 1), bottomLeft: Offset(0, 1),
      topMidDev: Offset(0, 0.1));

    test('defaults: no deviations → isStraight, midpoints at edge centers', () {
      const c = CropCorners(
        topLeft: Offset(0, 0), topRight: Offset(1, 0),
        bottomRight: Offset(1, 1), bottomLeft: Offset(0, 1));
      expect(c.isStraight, isTrue);
      expect(c.topMid, const Offset(0.5, 0));
      expect(c.leftMid, const Offset(0, 0.5));
    });

    test('a non-zero deviation offsets the midpoint from center and is not straight', () {
      expect(bent.isStraight, isFalse);
      expect(bent.topMid, const Offset(0.5, 0.1)); // center (0.5,0) + dev (0,0.1)
    });

    test('midpoint follows a moved corner (deviation is relative)', () {
      final moved = bent.copyWith(topRight: const Offset(0.8, 0));
      // topCenter = (0,0)+(0.8,0) /2 = (0.4,0); + dev (0,0.1) = (0.4,0.1)
      expect(moved.topMid, const Offset(0.4, 0.1));
    });

    test('copyWith preserves untouched fields (corner drag keeps a bend)', () {
      final moved = bent.copyWith(topLeft: const Offset(0.05, 0.05));
      expect(moved.topMidDev, const Offset(0, 0.1));
      expect(moved.topLeft, const Offset(0.05, 0.05));
    });

    test('== and hashCode include deviations', () {
      const same = CropCorners(
        topLeft: Offset(0, 0), topRight: Offset(1, 0),
        bottomRight: Offset(1, 1), bottomLeft: Offset(0, 1),
        topMidDev: Offset(0, 0.1));
      expect(bent, same);
      expect(bent.hashCode, same.hashCode);
      expect(bent, isNot(CropCorners.fullFrame));
    });

    test('clamp pulls resolved midpoints into [0,1]', () {
      const c = CropCorners(
        topLeft: Offset(0, 0), topRight: Offset(1, 0),
        bottomRight: Offset(1, 1), bottomLeft: Offset(0, 1),
        topMidDev: Offset(0, -0.5)); // topMid = (0.5,-0.5) → clamp to (0.5,0)
      expect(c.clamp().topMid.dy, 0.0);
    });
  });

  group('16-number persistence', () {
    const bent = CropCorners(
      topLeft: Offset(0.1, 0.2), topRight: Offset(0.9, 0.15),
      bottomRight: Offset(0.85, 0.95), bottomLeft: Offset(0.05, 0.9),
      topMidDev: Offset(0.0, 0.07), rightMidDev: Offset(-0.03, 0.0));

    test('toStorage emits 16 numbers and round-trips deviations', () {
      expect(bent.toStorage().split(',').length, 16);
      expect(CropCorners.tryParse(bent.toStorage()), bent);
    });

    test('legacy 8-number string parses as zero-deviation (straight)', () {
      final parsed = CropCorners.tryParse('0.1,0.2,0.9,0.15,0.85,0.95,0.05,0.9');
      expect(parsed, isNotNull);
      expect(parsed!.isStraight, isTrue);
      expect(parsed.topLeft, const Offset(0.1, 0.2));
    });

    test('rejects a 12-number string (neither 8 nor 16)', () {
      expect(CropCorners.tryParse(List.filled(12, '0').join(',')), isNull);
    });

    test('rejects a 16-number string with a non-finite token', () {
      final t = List.filled(16, '0.1')..[15] = 'NaN';
      expect(CropCorners.tryParse(t.join(',')), isNull);
    });
  });
}
