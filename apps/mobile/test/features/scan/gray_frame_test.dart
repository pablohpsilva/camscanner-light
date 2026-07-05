import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/scan/gray_frame.dart';

void main() {
  test('GrayFrame holds dims and a tightly-packed single-channel buffer', () {
    final f = GrayFrame(width: 4, height: 3, bytes: Uint8List(12));
    expect(f.width, 4);
    expect(f.height, 3);
    expect(f.bytes.length, f.width * f.height);
  });

  test('GrayFrame rejects a buffer whose length != width*height', () {
    expect(
      () => GrayFrame(width: 4, height: 3, bytes: Uint8List(11)),
      throwsA(isA<AssertionError>()),
    );
  });
}
