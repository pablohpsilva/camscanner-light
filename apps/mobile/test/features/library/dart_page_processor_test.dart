import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/library/dart_page_processor.dart';
import 'package:mobile/features/library/enhancer_mode.dart';
import 'package:mobile/features/library/hybrid_warper.dart';

Uint8List _jpeg(int w, int h) {
  final im = img.Image(width: w, height: h, numChannels: 3);
  img.fill(im, color: img.ColorRgb8(40, 40, 40));
  img.fillRect(im, x1: w ~/ 5, y1: h ~/ 5, x2: 4 * w ~/ 5, y2: 4 * h ~/ 5,
      color: img.ColorRgb8(220, 215, 205));
  return Uint8List.fromList(img.encodeJpg(im, quality: 92));
}

const _rect = CropCorners(
  topLeft: Offset(0.1, 0.1), topRight: Offset(0.9, 0.1),
  bottomRight: Offset(0.9, 0.9), bottomLeft: Offset(0.1, 0.9));

void main() {
  const p = DartPageProcessor(HybridWarper());

  test('none + fullFrame → null (nothing to do)', () async {
    final out = await p.process(_jpeg(200, 150), CropCorners.fullFrame, EnhancerMode.none);
    expect(out, isNull);
  });

  test('auto + fullFrame → enhanced JPEG (decodable)', () async {
    final out = await p.process(_jpeg(200, 150), CropCorners.fullFrame, EnhancerMode.auto);
    expect(out, isNotNull);
    expect(img.decodeImage(out!), isNotNull);
  });

  test('auto + straight crop → warped+enhanced JPEG, smaller than source', () async {
    final out = await p.process(_jpeg(400, 300), _rect, EnhancerMode.auto);
    expect(out, isNotNull);
    final d = img.decodeImage(out!)!;
    expect(d.width, lessThan(400)); // 80% crop
  });
}
