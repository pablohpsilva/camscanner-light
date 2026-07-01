import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:mobile/features/library/ocr/mlkit_ocr_engine.dart';

/// Renders black text on a white background as a JPEG.
Uint8List _textJpeg(String text) {
  final image = img.Image(width: 720, height: 220);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  img.drawString(image, text,
      font: img.arial48, x: 40, y: 80, color: img.ColorRgb8(0, 0, 0));
  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ML Kit recognizes real text on-device', (tester) async {
    const engine = MlKitOcrEngine();
    final result = await engine.recognize(_textJpeg('HELLO WORLD'));

    // ignore: avoid_print
    print('MLKIT recognized: "${result.text}" (${result.words.length} words)');
    final upper = result.text.toUpperCase();
    expect(upper.contains('HELLO'), isTrue,
        reason: 'ML Kit should recognize HELLO; got "${result.text}"');
    expect(upper.contains('WORLD'), isTrue,
        reason: 'ML Kit should recognize WORLD; got "${result.text}"');
    expect(result.words, isNotEmpty,
        reason: 'per-word boxes should be produced');
  });
}
