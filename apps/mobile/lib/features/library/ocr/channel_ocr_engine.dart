import 'package:flutter/services.dart';

import 'ocr_engine.dart';
import 'ocr_result.dart';

/// On-device OCR via a native platform channel — Apple Vision on iOS, ML Kit
/// (Kotlin) on Android — behind one uniform contract. This replaces the
/// `google_mlkit_text_recognition` Dart plugin so its iOS pods (the ~58 MB
/// bundled model) no longer link into the iOS build; see
/// docs/ios-vision-ocr-plan.md.
///
/// Channel contract (`camscanner/ocr`, method `recognize`, arg `jpeg`): the
/// native side returns `{text: String, words: [{text, left, top, right,
/// bottom}]}` with every box normalized 0..1 and a TOP-LEFT origin (each
/// platform converts its own coordinate space natively). This Dart layer only
/// maps, clamps, and degrades gracefully — it must never throw for a valid image.
class ChannelOcrEngine implements OcrEngine {
  final MethodChannel _channel;

  const ChannelOcrEngine([
    this._channel = const MethodChannel('camscanner/ocr'),
  ]);

  @override
  Future<OcrResult> recognize(Uint8List imageBytes) async {
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>(
        'recognize',
        {'jpeg': imageBytes},
      );
      if (raw == null) return OcrResult.empty;

      final text = (raw['text'] as String?) ?? '';
      final words = <OcrWordBox>[];
      for (final w in (raw['words'] as List? ?? const [])) {
        final m = (w as Map).cast<String, Object?>();
        words.add(OcrWordBox(
          text: (m['text'] as String?) ?? '',
          left: _norm(m['left']),
          top: _norm(m['top']),
          right: _norm(m['right']),
          bottom: _norm(m['bottom']),
        ));
      }
      return OcrResult(text: text, words: words);
    } on PlatformException {
      return OcrResult.empty;
    } on MissingPluginException {
      return OcrResult.empty;
    }
  }

  static double _norm(Object? v) =>
      ((v as num?)?.toDouble() ?? 0.0).clamp(0.0, 1.0);
}
