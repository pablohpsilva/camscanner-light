import 'dart:typed_data';

import 'ocr_result.dart';

/// Recognizes text in an image. Injectable (DIP) — the real on-device engine
/// (ML Kit / Tesseract) is chosen in O2; O1 ships only NoOp + a test fake.
/// Implementations do heavy work off the UI thread (their own concern).
abstract interface class OcrEngine {
  /// Recognizes text in [imageBytes] (a JPEG). Returns [OcrResult.empty] when
  /// there is no text. Must not throw for a valid-but-textless image.
  Future<OcrResult> recognize(Uint8List imageBytes);
}

/// O1 production default: recognizes nothing. The pipeline exists; a real
/// engine (O2) replaces this without touching callers.
class NoOpOcrEngine implements OcrEngine {
  const NoOpOcrEngine();
  @override
  Future<OcrResult> recognize(Uint8List imageBytes) async => OcrResult.empty;
}
