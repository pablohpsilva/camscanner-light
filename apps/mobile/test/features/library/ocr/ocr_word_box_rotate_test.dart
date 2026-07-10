import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/ocr/ocr_result.dart';

void main() {
  test('rotate90Cw moves a top-left box to the top-right', () {
    const b = OcrWordBox(text: 'x', left: 0, top: 0, right: 0.2, bottom: 0.1);
    final r = b.rotate90Cw();
    expect(r.left, closeTo(0.9, 1e-9));
    expect(r.top, closeTo(0.0, 1e-9));
    expect(r.right, closeTo(1.0, 1e-9));
    expect(r.bottom, closeTo(0.2, 1e-9));
    expect(r.text, 'x');
  });

  test('four rotations return the original box', () {
    const b = OcrWordBox(
      text: 'x',
      left: 0.1,
      top: 0.2,
      right: 0.5,
      bottom: 0.7,
    );
    var r = b;
    for (var i = 0; i < 4; i++) {
      r = r.rotate90Cw();
    }
    expect(r.left, closeTo(0.1, 1e-9));
    expect(r.top, closeTo(0.2, 1e-9));
    expect(r.right, closeTo(0.5, 1e-9));
    expect(r.bottom, closeTo(0.7, 1e-9));
  });
}
