import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/library/hybrid_warper.dart';

Uint8List _rectJpeg(int w, int h) {
  final image = img.Image(width: w, height: h, numChannels: 3);
  img.fill(image, color: img.ColorRgb8(10, 10, 10));
  img.fillRect(
    image,
    x1: w ~/ 5,
    y1: h ~/ 5,
    x2: 4 * w ~/ 5,
    y2: 4 * h ~/ 5,
    color: img.ColorRgb8(230, 230, 230),
  );
  return Uint8List.fromList(img.encodeJpg(image, quality: 90));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const warper = HybridWarper();

  testWidgets('bent-edge crop flattens to a decodable image on-device', (
    tester,
  ) async {
    const bent = CropCorners(
      topLeft: Offset(0.1, 0.12),
      topRight: Offset(0.9, 0.1),
      bottomRight: Offset(0.9, 0.9),
      bottomLeft: Offset(0.1, 0.88),
      topMidDev: Offset(0, -0.06),
      bottomMidDev: Offset(0, 0.05),
    );
    final out = await warper.warp(_rectJpeg(1200, 900), bent);
    expect(out, isNotNull);
    expect(img.decodeImage(out!), isNotNull);
  });

  testWidgets('large curved image flattens within budget', (tester) async {
    const bent = CropCorners(
      topLeft: Offset(0.05, 0.05),
      topRight: Offset(0.95, 0.05),
      bottomRight: Offset(0.95, 0.95),
      bottomLeft: Offset(0.05, 0.95),
      leftMidDev: Offset(-0.04, 0),
    );
    final bytes = _rectJpeg(3000, 2000);
    final start = DateTime.now();
    final out = await warper.warp(bytes, bent);
    final ms = DateTime.now().difference(start).inMilliseconds;
    expect(out, isNotNull);
    expect(ms, lessThan(4000), reason: 'curved warp budget; took ${ms}ms');
  });

  testWidgets('straight crop still routes through homography', (tester) async {
    const straight = CropCorners(
      topLeft: Offset(0.1, 0.1),
      topRight: Offset(0.9, 0.1),
      bottomRight: Offset(0.9, 0.9),
      bottomLeft: Offset(0.1, 0.9),
    );
    final out = await warper.warp(_rectJpeg(800, 600), straight);
    expect(out, isNotNull); // non-null flat; perspective path exercised
  });
}
