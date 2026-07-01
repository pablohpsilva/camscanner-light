import 'dart:io';
import 'dart:typed_data';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;

import 'ocr_engine.dart';
import 'ocr_result.dart';

/// On-device OCR via Google ML Kit text recognition (Latin script; bundled model,
/// no downloads, nothing leaves the device). Extracts the full text plus per-word
/// boxes normalized (0..1) to the image — the boxes feed the searchable PDF layer.
///
/// ML Kit only runs on a real iOS/Android device (native), so this is exercised by
/// on-device integration tests; host tests use a fake through the [OcrEngine] seam.
class MlKitOcrEngine implements OcrEngine {
  const MlKitOcrEngine();

  @override
  Future<OcrResult> recognize(Uint8List imageBytes) async {
    // Image dimensions (to normalize the pixel boxes ML Kit returns).
    final decoded = img.decodeImage(imageBytes);
    final w = (decoded?.width ?? 0).toDouble();
    final h = (decoded?.height ?? 0).toDouble();

    // ML Kit reads from a file path; write the bytes to a short-lived temp file.
    final dir = await Directory.systemTemp.createTemp('mlkit_ocr');
    final file = File('${dir.path}/img.jpg')..writeAsBytesSync(imageBytes);
    final recognizer = TextRecognizer();
    try {
      final recognized =
          await recognizer.processImage(InputImage.fromFilePath(file.path));
      final words = <OcrWordBox>[];
      if (w > 0 && h > 0) {
        for (final block in recognized.blocks) {
          for (final line in block.lines) {
            for (final el in line.elements) {
              final r = el.boundingBox;
              words.add(OcrWordBox(
                text: el.text,
                left: (r.left / w).clamp(0.0, 1.0),
                top: (r.top / h).clamp(0.0, 1.0),
                right: (r.right / w).clamp(0.0, 1.0),
                bottom: (r.bottom / h).clamp(0.0, 1.0),
              ));
            }
          }
        }
      }
      return OcrResult(text: recognized.text, words: words);
    } finally {
      await recognizer.close();
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {/* best-effort temp cleanup */}
    }
  }
}
