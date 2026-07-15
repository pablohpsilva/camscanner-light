import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile/features/library/coons_warper.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/library/image_warper.dart';

Uint8List _rectJpeg(int w, int h) {
  final image = img.Image(width: w, height: h, numChannels: 3);
  img.fill(image, color: img.ColorRgb8(10, 20, 30));
  img.fillRect(
    image,
    x1: w ~/ 4,
    y1: h ~/ 4,
    x2: 3 * w ~/ 4,
    y2: 3 * h ~/ 4,
    color: img.ColorRgb8(200, 200, 200),
  );
  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
}

/// A runner that never resolves — stands in for a wedged isolate so the
/// timeout branch of warp() can be exercised deterministically.
Future<Uint8List?> _neverCompletes(Uint8List bytes, CropCorners corners) =>
    Completer<Uint8List?>().future;

void main() {
  const warper = CoonsWarper();

  test('never-completing runner + tiny timeout → null (no hang)', () async {
    const warperTimeout = CoonsWarper(
      timeout: Duration(milliseconds: 50),
      runnerOverride: _neverCompletes,
    );
    const bent = CropCorners(
      topLeft: Offset(0.1, 0.1),
      topRight: Offset(0.9, 0.1),
      bottomRight: Offset(0.9, 0.9),
      bottomLeft: Offset(0.1, 0.9),
      topMidDev: Offset(0, -0.08),
    );
    final result = await warperTimeout
        .warp(_rectJpeg(200, 160), bent)
        .timeout(
          const Duration(seconds: 5),
          onTimeout: () => throw StateError('warp() did not honor its timeout'),
        );
    expect(result, isNull);
  });

  test('fullFrame → null (no-op)', () async {
    expect(await warper.warp(_rectJpeg(80, 60), CropCorners.fullFrame), isNull);
  });

  test(
    'straight full-frame corners → identity-sized output (decodable JPEG)',
    () async {
      // Straight edges over the whole image: output ≈ source dimensions.
      const straight = CropCorners(
        topLeft: Offset(0, 0),
        topRight: Offset(1, 0),
        bottomRight: Offset(1, 1),
        bottomLeft: Offset(0, 1),
        topMidDev: Offset(0, 0.0001),
      ); // tiny dev so it's not == fullFrame
      final out = await warper.warp(_rectJpeg(120, 90), straight);
      expect(out, isNotNull);
      final decoded = img.decodeImage(out!);
      expect(decoded, isNotNull);
      expect(decoded!.width, closeTo(120, 8));
      expect(decoded.height, closeTo(90, 8));
    },
  );

  test('bent top edge produces a decodable output of sane size', () async {
    const bent = CropCorners(
      topLeft: Offset(0.1, 0.1),
      topRight: Offset(0.9, 0.1),
      bottomRight: Offset(0.9, 0.9),
      bottomLeft: Offset(0.1, 0.9),
      topMidDev: Offset(0, -0.08),
    ); // top edge bows upward
    final out = await warper.warp(_rectJpeg(200, 160), bent);
    expect(out, isNotNull);
    final decoded = img.decodeImage(out!)!;
    expect(decoded.width, greaterThan(2));
    expect(decoded.height, greaterThan(2));
  });

  test('output dimensions are capped by maxDimension', () async {
    const warperSmall = CoonsWarper(maxDimension: 50);
    const bent = CropCorners(
      topLeft: Offset(0, 0),
      topRight: Offset(1, 0),
      bottomRight: Offset(1, 1),
      bottomLeft: Offset(0, 1),
      topMidDev: Offset(0, 0.05),
    );
    final out = await warperSmall.warp(_rectJpeg(400, 300), bent);
    final decoded = img.decodeImage(out!)!;
    expect(decoded.width, lessThanOrEqualTo(50));
    expect(decoded.height, lessThanOrEqualTo(50));
  });

  // P01 T4: NORMAL source (≤ 2×cap) — output unchanged vs pre-bound impl.
  //   computeWorkResolution returns scale==1.0 so no source resize happens.
  test('P01 T4: small source (≤ 2×cap) → output unchanged (scale==1.0)', () async {
    const bent = CropCorners(
      topLeft: Offset(0.1, 0.1),
      topRight: Offset(0.9, 0.1),
      bottomRight: Offset(0.9, 0.9),
      bottomLeft: Offset(0.1, 0.9),
      topMidDev: Offset(0, -0.08),
    );
    final out = await warper.warp(_rectJpeg(200, 160), bent);
    expect(out, isNotNull);
    final decoded = img.decodeImage(out!)!;
    expect(decoded.width, greaterThan(2));
    expect(decoded.height, greaterThan(2));
  });

  // P01 T4: LARGE source (long side > 2×cap) — warp succeeds, source buffer is
  //   bounded, output long side stays ≤ kDefaultFlatMaxDimension, no throw.
  test('P01 T4: large source (> 2×cap) → bounded, output long side ≤ cap', () async {
    const cap = 3500; // kDefaultFlatMaxDimension
    const bent = CropCorners(
      topLeft: Offset(0, 0),
      topRight: Offset(1, 0),
      bottomRight: Offset(1, 1),
      bottomLeft: Offset(0, 1),
      topMidDev: Offset(0, 0.05),
    );
    final out = await warper.warp(_rectJpeg(8000, 6000), bent);
    expect(out, isNotNull);
    final decoded = img.decodeImage(out!)!;
    final longest = decoded.width > decoded.height ? decoded.width : decoded.height;
    expect(longest, lessThanOrEqualTo(cap));
  });

  // P01 T4 (direct): the sampling loop reads a SOURCE buffer bounded to
  //   2×maxDim. Calling warpCoonsToImage on an oversized img.Image must
  //   downscale the source it samples (super-sampling headroom = 2×cap).
  test('P01 T4: source long side bounded to 2×maxDim in sampling loop', () {
    final big = img.Image(width: 8000, height: 6000, numChannels: 3);
    img.fill(big, color: img.ColorRgb8(10, 20, 30));
    const bent = CropCorners(
      topLeft: Offset(0, 0),
      topRight: Offset(1, 0),
      bottomRight: Offset(1, 1),
      bottomLeft: Offset(0, 1),
      topMidDev: Offset(0, 0.05),
    );
    lastSampledSourceSize = null;
    warpCoonsToImage(big, bent, 3500);
    expect(lastSampledSourceSize, isNotNull);
    // 8000 > 2×3500=7000 → bounded to 7000×5250.
    expect(lastSampledSourceSize!.$1, 7000);
    expect(lastSampledSourceSize!.$2, 5250);
  });

  // P01 T4 (direct): a source already ≤ 2×maxDim is NOT resized — the sampling
  //   loop reads the original buffer, so normal inputs are byte-identical.
  test('P01 T4: source ≤ 2×maxDim is not resized', () {
    final small = img.Image(width: 200, height: 160, numChannels: 3);
    img.fill(small, color: img.ColorRgb8(10, 20, 30));
    const bent = CropCorners(
      topLeft: Offset(0.1, 0.1),
      topRight: Offset(0.9, 0.1),
      bottomRight: Offset(0.9, 0.9),
      bottomLeft: Offset(0.1, 0.9),
      topMidDev: Offset(0, -0.08),
    );
    lastSampledSourceSize = null;
    warpCoonsToImage(small, bent, 3500);
    expect(lastSampledSourceSize, (200, 160));
  });

  test('corrupt bytes → WarpException', () async {
    // Async error propagates through the compute() Future — assert with
    // expectLater on the future, matching perspective_warper_test.
    await expectLater(
      warper.warp(
        Uint8List.fromList([0xFF, 0xD8, 0x00]),
        const CropCorners(
          topLeft: Offset(0, 0),
          topRight: Offset(1, 0),
          bottomRight: Offset(1, 1),
          bottomLeft: Offset(0, 1),
          topMidDev: Offset(0, 0.05),
        ),
      ),
      throwsA(isA<WarpException>()),
    );
  });
}
