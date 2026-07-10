import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/library/enhancer_mode.dart';
import 'package:mobile/features/library/native_page_processor.dart';

Uint8List _cap(int w, int h) {
  final p = img.Image(width: w, height: h, numChannels: 3);
  img.fill(p, color: img.ColorRgb8(70, 70, 70));
  img.fillRect(
    p,
    x1: (w * .08).round(),
    y1: (h * .10).round(),
    x2: (w * .92).round(),
    y2: (h * .90).round(),
    color: img.ColorRgb8(220, 218, 210),
  );
  return Uint8List.fromList(img.encodeJpg(p, quality: 92));
}

const _straight = CropCorners(
  topLeft: Offset(0.08, 0.10),
  topRight: Offset(0.92, 0.10),
  bottomRight: Offset(0.92, 0.90),
  bottomLeft: Offset(0.08, 0.90),
);
const _bent = CropCorners(
  topLeft: Offset(0.08, 0.10),
  topRight: Offset(0.92, 0.10),
  bottomRight: Offset(0.92, 0.90),
  bottomLeft: Offset(0.08, 0.90),
  topMidDev: Offset(0, -0.05),
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const p = NativePageProcessor();

  test('none + straight crop → warped JPEG, long side ≤ 3500, fast', () async {
    final s = Stopwatch()..start();
    final out = await p.process(_cap(6000, 4500), _straight, EnhancerMode.none);
    // ignore: avoid_print
    print('NP1 none/straight: ${s.elapsedMilliseconds}ms');
    expect(out, isNotNull);
    final d = img.decodeImage(out!)!;
    expect(d.width <= 3500 && d.height <= 3500, isTrue);
    expect(d.width, greaterThan(2));
  });

  test('bent crop → null (defers to Dart Coons)', () async {
    final out = await p.process(_cap(1200, 900), _bent, EnhancerMode.none);
    expect(out, isNull);
  });

  test('corrupt bytes → null (defers to fallback)', () async {
    final out = await p.process(
      Uint8List.fromList([0xFF, 0xD8, 0x00, 0x01]),
      _straight,
      EnhancerMode.none,
    );
    expect(out, isNull);
  });
}
