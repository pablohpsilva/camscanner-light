import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile/features/library/export/export_quality.dart';
import 'package:mobile/features/library/export/image_compressor.dart';

Uint8List _jpeg(int w, int h, {int? orientation}) {
  final image = img.Image(width: w, height: h);
  // Fill with a gradient so JPEG has real content (not a flat block).
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      image.setPixelRgb(x, y, x % 256, y % 256, (x + y) % 256);
    }
  }
  if (orientation != null) image.exif.imageIfd.orientation = orientation;
  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
}

void main() {
  const compressor = ImageLibraryCompressor();

  test('original returns the input bytes verbatim (byte-identical)', () async {
    final input = _jpeg(400, 300);
    final out = await compressor.compress(input, ExportQuality.original);
    expect(out, equals(input)); // element-wise: same bytes, no re-encode
  });

  test('low yields fewer bytes and a smaller long edge for a large image',
      () async {
    final input = _jpeg(3000, 2000);
    final out = await compressor.compress(input, ExportQuality.low);
    expect(out.length, lessThan(input.length));
    final decoded = img.decodeImage(out)!;
    expect(decoded.width, 1600); // long edge capped at low.maxDimension
    expect(decoded.height, lessThan(2000));
  });

  test('never upscales a small image', () async {
    final input = _jpeg(800, 600); // long edge 800 < low cap 1600
    final out = await compressor.compress(input, ExportQuality.low);
    final decoded = img.decodeImage(out)!;
    expect(decoded.width, 800);
    expect(decoded.height, 600);
  });

  test('malformed input falls back to verbatim (no throw)', () async {
    final garbage = Uint8List.fromList(List<int>.filled(64, 0x7F));
    final out = await compressor.compress(garbage, ExportQuality.low);
    expect(out, garbage);
  });

  test('re-encode bakes EXIF orientation into the pixels', () async {
    // 100x60 tagged orientation 6 (90° CW) => baked dims become 60x100.
    final input = _jpeg(100, 60, orientation: 6);
    final out = await compressor.compress(input, ExportQuality.high);
    final decoded = img.decodeImage(out)!;
    expect(decoded.width, 60);
    expect(decoded.height, 100);
    final o = decoded.exif.imageIfd.orientation;
    expect(o == null || o == 1, isTrue); // tag cleared/absent after bake
  });
}
