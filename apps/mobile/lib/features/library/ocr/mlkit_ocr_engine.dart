import 'dart:async';
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
  /// Creates the native recognizer. Injectable so host tests can drive the
  /// timeout wiring with a fake; production default is a real [TextRecognizer].
  final TextRecognizer Function() recognizerFactory;

  /// Upper bound on a single [TextRecognizer.processImage] call. A wedged
  /// native recognizer would otherwise hang the OCR future forever. Generous —
  /// a real page must never trip it; on trip we return the same empty result an
  /// unreadable image yields (never throw).
  final Duration timeout;

  const MlKitOcrEngine({
    this.recognizerFactory = _newTextRecognizer,
    this.timeout = const Duration(seconds: 20),
  });

  @override
  Future<OcrResult> recognize(Uint8List imageBytes) async {
    // Image dimensions (to normalize the pixel boxes ML Kit returns).
    final decoded = img.decodeImage(imageBytes);
    final w = (decoded?.width ?? 0).toDouble();
    final h = (decoded?.height ?? 0).toDouble();

    // ML Kit reads from a file path; write the bytes to a short-lived temp file.
    final dir = await Directory.systemTemp.createTemp('mlkit_ocr');
    final file = File('${dir.path}/img.jpg')..writeAsBytesSync(imageBytes);
    final recognizer = recognizerFactory();
    try {
      final RecognizedText recognized;
      try {
        recognized = await recognizer
            .processImage(InputImage.fromFilePath(file.path))
            .timeout(timeout);
      } on TimeoutException {
        // A wedged native recognizer hung past [timeout]: yield the same
        // "nothing recognized" result an unreadable image gives (the finally
        // block below still closes the recognizer and cleans up the temp dir).
        return OcrResult.empty;
      }
      final words = <OcrWordBox>[];
      if (w > 0 && h > 0) {
        for (final block in recognized.blocks) {
          for (final line in block.lines) {
            for (final el in line.elements) {
              final r = el.boundingBox;
              words.add(
                OcrWordBox(
                  text: el.text,
                  left: (r.left / w).clamp(0.0, 1.0),
                  top: (r.top / h).clamp(0.0, 1.0),
                  right: (r.right / w).clamp(0.0, 1.0),
                  bottom: (r.bottom / h).clamp(0.0, 1.0),
                ),
              );
            }
          }
        }
      }
      return OcrResult(text: recognized.text, words: words);
    } finally {
      await recognizer.close();
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {
        /* best-effort temp cleanup */
      }
    }
  }
}

/// Production default for [MlKitOcrEngine.recognizerFactory]: a real ML Kit
/// Latin-script recognizer. Top-level so the constructor stays `const`.
TextRecognizer _newTextRecognizer() => TextRecognizer();
