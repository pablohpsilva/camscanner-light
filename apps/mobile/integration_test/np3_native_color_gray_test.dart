import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/library/enhancer_mode.dart';
import 'package:mobile/features/library/native_page_processor.dart';

Uint8List _color(int w, int h) {
  final im = img.Image(width: w, height: h, numChannels: 3);
  img.fill(im, color: img.ColorRgb8(200, 120, 60)); // clearly non-gray
  return Uint8List.fromList(img.encodeJpg(im, quality: 92));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const p = NativePageProcessor();

  test('grayscale: output R==G==B', () async {
    final out = await p.process(
      _color(300, 200),
      CropCorners.fullFrame,
      EnhancerMode.grayscale,
    );
    expect(out, isNotNull);
    final d = img.decodeImage(out!)!;
    final px = d.getPixel(150, 100);
    expect((px.r - px.g).abs() <= 2 && (px.g - px.b).abs() <= 2, isTrue);
  });

  test('color: stays colored (R != B), decodable, same size', () async {
    final out = await p.process(
      _color(300, 200),
      CropCorners.fullFrame,
      EnhancerMode.color,
    );
    expect(out, isNotNull);
    final d = img.decodeImage(out!)!;
    expect(d.width, 300);
    final px = d.getPixel(150, 100);
    expect((px.r - px.b).abs() > 20, isTrue);
  });
}
