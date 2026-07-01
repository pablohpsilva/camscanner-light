import 'dart:typed_data';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile/features/library/coons_warper.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/library/image_warper.dart';

Uint8List _rectJpeg(int w, int h) {
  final image = img.Image(width: w, height: h, numChannels: 3);
  img.fill(image, color: img.ColorRgb8(10, 20, 30));
  img.fillRect(image, x1: w ~/ 4, y1: h ~/ 4, x2: 3 * w ~/ 4, y2: 3 * h ~/ 4,
      color: img.ColorRgb8(200, 200, 200));
  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
}

void main() {
  const warper = CoonsWarper();

  test('fullFrame → null (no-op)', () async {
    expect(await warper.warp(_rectJpeg(80, 60), CropCorners.fullFrame), isNull);
  });

  test('straight full-frame corners → identity-sized output (decodable JPEG)',
      () async {
    // Straight edges over the whole image: output ≈ source dimensions.
    const straight = CropCorners(
      topLeft: Offset(0, 0), topRight: Offset(1, 0),
      bottomRight: Offset(1, 1), bottomLeft: Offset(0, 1),
      topMidDev: Offset(0, 0.0001)); // tiny dev so it's not == fullFrame
    final out = await warper.warp(_rectJpeg(120, 90), straight);
    expect(out, isNotNull);
    final decoded = img.decodeImage(out!);
    expect(decoded, isNotNull);
    expect(decoded!.width, closeTo(120, 8));
    expect(decoded.height, closeTo(90, 8));
  });

  test('bent top edge produces a decodable output of sane size', () async {
    const bent = CropCorners(
      topLeft: Offset(0.1, 0.1), topRight: Offset(0.9, 0.1),
      bottomRight: Offset(0.9, 0.9), bottomLeft: Offset(0.1, 0.9),
      topMidDev: Offset(0, -0.08)); // top edge bows upward
    final out = await warper.warp(_rectJpeg(200, 160), bent);
    expect(out, isNotNull);
    final decoded = img.decodeImage(out!)!;
    expect(decoded.width, greaterThan(2));
    expect(decoded.height, greaterThan(2));
  });

  test('output dimensions are capped by maxDimension', () async {
    const warperSmall = CoonsWarper(maxDimension: 50);
    const bent = CropCorners(
      topLeft: Offset(0, 0), topRight: Offset(1, 0),
      bottomRight: Offset(1, 1), bottomLeft: Offset(0, 1),
      topMidDev: Offset(0, 0.05));
    final out = await warperSmall.warp(_rectJpeg(400, 300), bent);
    final decoded = img.decodeImage(out!)!;
    expect(decoded.width, lessThanOrEqualTo(50));
    expect(decoded.height, lessThanOrEqualTo(50));
  });

  test('corrupt bytes → WarpException', () async {
    // Async error propagates through the compute() Future — assert with
    // expectLater on the future, matching perspective_warper_test.
    await expectLater(
      warper.warp(Uint8List.fromList([0xFF, 0xD8, 0x00]),
          const CropCorners(
              topLeft: Offset(0, 0), topRight: Offset(1, 0),
              bottomRight: Offset(1, 1), bottomLeft: Offset(0, 1),
              topMidDev: Offset(0, 0.05))),
      throwsA(isA<WarpException>()),
    );
  });
}
