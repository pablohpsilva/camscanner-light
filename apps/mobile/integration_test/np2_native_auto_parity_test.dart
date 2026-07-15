import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:mobile/features/library/auto_enhancer.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/library/enhancer_mode.dart';
import 'package:mobile/features/library/native_page_processor.dart';
import 'package:mobile/features/library/perspective_warper.dart'
    show kDefaultFlatMaxDimension;

Uint8List _doc(int w, int h) {
  final im = img.Image(width: w, height: h, numChannels: 3);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final shade = 1.0 - 0.4 * (x + y) / (w + h);
      var r = (235 * shade).round(),
          g = (225 * shade).round(),
          b = (205 * shade).round();
      if (x > w ~/ 8 &&
          x < 7 * w ~/ 8 &&
          (y % 40) < 16 &&
          y > h ~/ 8 &&
          y < 7 * h ~/ 8) {
        r = 35;
        g = 33;
        b = 30;
      }
      im.setPixelRgb(x, y, r.clamp(0, 255), g.clamp(0, 255), b.clamp(0, 255));
    }
  }
  return Uint8List.fromList(img.encodeJpg(im, quality: 95));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const p = NativePageProcessor();

  test('native Auto ≈ Dart Auto (full frame)', () async {
    final bytes = _doc(1600, 1200);
    final nativeOut = await p.process(
      bytes,
      CropCorners.fullFrame,
      EnhancerMode.auto,
    );
    expect(nativeOut, isNotNull);

    // Dart reference (bake + autoEnhanceOriented, then encode q95).
    final baked = img.bakeOrientation(img.decodeImage(bytes)!);
    final dartImg = autoEnhanceOriented(baked);
    final nImg = img.decodeImage(nativeOut!)!;
    expect(nImg.width, dartImg.width);
    expect(nImg.height, dartImg.height);

    final nb = nImg.getBytes(order: img.ChannelOrder.rgb);
    final db = dartImg.getBytes(order: img.ChannelOrder.rgb);
    var sum = 0, maxd = 0;
    for (var i = 0; i < nb.length; i++) {
      final d = (nb[i] - db[i]).abs();
      sum += d;
      if (d > maxd) maxd = d;
    }
    final mean = sum / nb.length;
    // ignore: avoid_print
    print('NP2 native-vs-dart Auto: mean=${mean.toStringAsFixed(3)} max=$maxd');
    expect(mean, lessThan(2.0), reason: 'quality parity gate');
  });

  // P01 T2: an over-cap full-frame input must be processed at a bounded working
  // resolution (the float pass no longer runs at raw capture resolution). This
  // exercises the computeWorkResolution downscale branch (scale != 1.0) that the
  // 1600x1200 fixture above never hits.
  test('native Auto caps an over-cap full-frame input to the output cap', () async {
    const long = 4600, short = 3450; // long side > kDefaultFlatMaxDimension (3500)
    final bytes = _doc(long, short);
    final nativeOut = await p.process(
      bytes,
      CropCorners.fullFrame,
      EnhancerMode.auto,
    );
    expect(nativeOut, isNotNull, reason: 'over-cap Auto must still produce output');

    final nImg = img.decodeImage(nativeOut!)!;
    // The working resolution (and thus the output) is bounded by the cap: the
    // long side is downscaled to exactly kDefaultFlatMaxDimension.
    expect(
      nImg.width,
      kDefaultFlatMaxDimension,
      reason: 'over-cap long side must be downscaled to the cap',
    );
    expect(nImg.width <= kDefaultFlatMaxDimension, isTrue);
    expect(nImg.height <= kDefaultFlatMaxDimension, isTrue);
    // Aspect ratio preserved (proportional downscale).
    expect(
      ((nImg.width / nImg.height) - (long / short)).abs(),
      lessThan(0.02),
    );
    // ignore: avoid_print
    print('NP2 over-cap: in=${long}x$short out=${nImg.width}x${nImg.height}');
  });
}
