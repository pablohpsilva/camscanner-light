import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile/features/library/preview_proxy.dart';

void main() {
  group('previewProxyJpeg', () {
    // The live-preview bug: `img.decodeImage` does not just return null on bad
    // input — it can THROW (a RangeError while a decoder probes a tiny buffer).
    // If the proxy lets that escape, the compute() isolate errors and the live
    // filter preview never appears (falls back to Image.file). These pin the
    // "never throws — returns bytes unchanged on any failure" contract that the
    // g4/e5 on-device integration tests exercise for real.

    test('returns the input unchanged on empty bytes (never throws)', () {
      final empty = Uint8List(0);
      expect(() => previewProxyJpeg(empty), returnsNormally);
      expect(previewProxyJpeg(empty), same(empty));
    });

    test('returns the input unchanged on tiny/undecodable bytes '
        '(the 160-byte seed JPEG that decodeImage chokes on)', () {
      // A 160-byte buffer that starts like a JPEG but is not decodable — the
      // exact shape that threw `RangeError ... 0..159: 160` on device.
      final tiny = Uint8List.fromList(
        <int>[0xFF, 0xD8, 0xFF, 0xE0, ...List<int>.filled(156, 0)],
      );
      expect(() => previewProxyJpeg(tiny), returnsNormally);
      expect(previewProxyJpeg(tiny), same(tiny));
    });

    test('returns a decodable small image unchanged (≤1080 long side)', () {
      final src = img.Image(width: 10, height: 8);
      final jpeg = Uint8List.fromList(img.encodeJpg(src));
      final out = previewProxyJpeg(jpeg);
      // Small enough to skip the resize → the same bytes come back.
      expect(out, same(jpeg));
    });

    test('downsizes an image whose long side exceeds 1080 px', () {
      final src = img.Image(width: 2000, height: 1000);
      final jpeg = Uint8List.fromList(img.encodeJpg(src));
      final out = previewProxyJpeg(jpeg);
      expect(out, isNot(same(jpeg)));
      final decoded = img.decodeImage(out)!;
      expect(decoded.width, lessThanOrEqualTo(1080));
      expect(decoded.height, lessThanOrEqualTo(1080));
    });
  });
}
