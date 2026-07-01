import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile/features/library/ocr/ocr_result.dart';
import 'package:mobile/features/library/page_image.dart';
import 'package:mobile/features/library/pdf/ocr_pdf_text_layer.dart';
import 'package:mobile/features/library/pdf/pdf_builder.dart';

String _dec(Uint8List b) => latin1.decode(b, allowInvalid: true);

void main() {
  // A tiny JPEG for the image page so the PDF builder can read it.
  late Directory tmp;
  late String jpegPath;

  setUpAll(() {
    tmp = Directory.systemTemp.createTempSync('ocr_layer_test');
    final bytes = img.encodeJpg(img.Image(width: 100, height: 200));
    jpegPath = '${tmp.path}/page.jpg';
    File(jpegPath).writeAsBytesSync(bytes);
  });

  tearDownAll(() => tmp.deleteSync(recursive: true));

  PageImage pageWithWords(List<OcrWordBox> words) => PageImage(
        position: 1,
        imagePath: jpegPath,
        ocrWords: words,
      );

  test(
      'OCR words embedded as invisible text: both words present in PDF bytes',
      () async {
    final words = [
      const OcrWordBox(text: 'HELLO', left: 0.0, top: 0.0, right: 0.2, bottom: 0.1),
      const OcrWordBox(text: 'WORLD', left: 0.0, top: 0.2, right: 0.2, bottom: 0.3),
    ];
    // compress:false so the invisible text is not deflated and is grep-able.
    final pdf = await PdfBuilder(textLayer: const OcrPdfTextLayer())
        .build([pageWithWords(words)], compress: false);

    final s = _dec(pdf);
    expect(s.contains('HELLO'), isTrue, reason: 'HELLO must be embedded as invisible text');
    expect(s.contains('WORLD'), isTrue, reason: 'WORLD must be embedded as invisible text');
    // The image is also present.
    expect(s.contains('/DCTDecode'), isTrue, reason: 'JPEG image must still be embedded');
  });

  test('image-only page (no ocrWords) produces PDF with no word text', () async {
    final pdf = await PdfBuilder(textLayer: const OcrPdfTextLayer())
        .build([pageWithWords(const [])], compress: false);

    final s = _dec(pdf);
    // No recognizable words — only the image.
    expect(s.contains('HELLO'), isFalse);
    expect(s.contains('WORLD'), isFalse);
    expect(s.contains('/DCTDecode'), isTrue,
        reason: 'image must still be embedded even without OCR words');
  });

  test('blank-text words (whitespace only) are skipped', () async {
    final words = [
      const OcrWordBox(text: '   ', left: 0.0, top: 0.0, right: 0.1, bottom: 0.1),
      const OcrWordBox(text: 'VISIBLE', left: 0.1, top: 0.1, right: 0.3, bottom: 0.2),
    ];
    final pdf = await PdfBuilder(textLayer: const OcrPdfTextLayer())
        .build([pageWithWords(words)], compress: false);

    final s = _dec(pdf);
    expect(s.contains('VISIBLE'), isTrue);
  });
}
