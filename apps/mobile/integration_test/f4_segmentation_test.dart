import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:mobile/features/scan/opencv_edge_detector.dart';

/// A `page` rectangle (uniform gray `page`) on a `desk` background.
Uint8List _pageOn({required int desk, required int page}) {
  final image = img.Image(width: 800, height: 600, numChannels: 3);
  img.fill(image, color: img.ColorRgb8(desk, desk, desk));
  img.fillRect(
    image,
    x1: 150,
    y1: 110,
    x2: 650,
    y2: 490,
    color: img.ColorRgb8(page, page, page),
  );
  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
}

/// Uniform image — no page.
Uint8List _uniform(int v) {
  final image = img.Image(width: 800, height: 600, numChannels: 3);
  img.fill(image, color: img.ColorRgb8(v, v, v));
  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('f4: segmentation detection (on-device, real libdartcv)', () {
    const detector = OpenCvEdgeDetector();
    // Expected page bounds normalized: x [150/800,650/800]=[0.188,0.813],
    // y [110/600,490/600]=[0.183,0.817]. Tolerance covers blur + close drift.
    const tol = 0.08;

    void expectHugsPage(dynamic result, String reason) {
      expect(result, isNotNull, reason: reason);
      final c = result!.corners;
      expect(c.topLeft.dx, closeTo(0.188, tol));
      expect(c.topLeft.dy, closeTo(0.183, tol));
      expect(c.bottomRight.dx, closeTo(0.813, tol));
      expect(c.bottomRight.dy, closeTo(0.817, tol));
    }

    test('page brighter than desk → bright-polarity quad', () async {
      expectHugsPage(
        await detector.detect(_pageOn(desk: 55, page: 225)),
        'bright page on a dark desk must segment',
      );
    });

    test('page darker than desk → dark-polarity quad', () async {
      expectHugsPage(
        await detector.detect(_pageOn(desk: 235, page: 150)),
        'darker page on a light desk must segment via the inverse mask',
      );
    });

    test('uniform frame → null (no page)', () async {
      expect(await detector.detect(_uniform(200)), isNull);
    });
  });
}
