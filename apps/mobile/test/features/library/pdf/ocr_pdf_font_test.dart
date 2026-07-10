import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:mobile/features/library/ocr/ocr_result.dart';
import 'package:mobile/features/library/page_image.dart';
import 'package:mobile/features/library/pdf/ocr_pdf_text_layer.dart';
import 'package:mobile/features/library/pdf/pdf_builder.dart';

/// Captures `print` output (dart_pdf logs missing-glyph warnings via print).
Future<List<String>> _capturePrints(Future<void> Function() body) async {
  final logs = <String>[];
  await runZoned(
    body,
    zoneSpecification:
        ZoneSpecification(print: (s, p, z, line) => logs.add(line)),
  );
  return logs;
}

PageImage _pageWithWords(List<OcrWordBox> words) =>
    PageImage(position: 1, imagePath: '/nonexistent.jpg', ocrWords: words);

/// Renders [overlay] into a page and counts dart_pdf's "Unable to find a font
/// to draw" warnings — each such warning is a glyph that gets stroked as a
/// visible .notdef box-with-X (the reported bug).
Future<int> _missingGlyphWarnings(List<pw.Widget> overlay) async {
  final logs = await _capturePrints(() async {
    final doc = pw.Document(compress: false);
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(600, 800),
        build: (c) => pw.Stack(children: overlay),
      ),
    );
    await doc.save();
  });
  return logs.where((l) => l.contains('Unable to find a font')).length;
}

void main() {
  // OCR output (ML Kit) routinely contains these non-Latin-1 characters.
  const problemWords = [
    OcrWordBox(text: 'em—dash', left: .1, top: .1, right: .5, bottom: .16),
    OcrWordBox(text: '“curly”', left: .1, top: .2, right: .5, bottom: .26),
    OcrWordBox(text: 'ellipsis…', left: .1, top: .3, right: .5, bottom: .36),
  ];

  test('OCR overlay with a Unicode font draws NO missing-glyph box', () async {
    final fontData = await File('fonts/IBMPlexMono-Regular.ttf').readAsBytes();
    final ttf = pw.Font.ttf(fontData.buffer.asByteData());
    final overlay = const OcrPdfTextLayer()
        .overlayFor(_pageWithWords(problemWords), 600, 800, font: ttf);
    expect(
      await _missingGlyphWarnings(overlay),
      0,
      reason: 'a Unicode font resolves em-dash/curly-quotes/ellipsis, so '
          'dart_pdf never strokes a visible .notdef box-with-X',
    );
  });

  test('regression: without a Unicode font those glyphs are missing', () async {
    final overlay = const OcrPdfTextLayer()
        .overlayFor(_pageWithWords(problemWords), 600, 800);
    expect(
      await _missingGlyphWarnings(overlay),
      greaterThan(0),
      reason: 'documents the original bug: default Helvetica cannot draw them',
    );
  });

  test('PdfBuilder threads the OCR font end-to-end (no missing-glyph box)',
      () async {
    final tmp = Directory.systemTemp.createTempSync();
    final jpegPath = '${tmp.path}/page.jpg';
    File(jpegPath)
        .writeAsBytesSync(img.encodeJpg(img.Image(width: 100, height: 200)));
    final page =
        PageImage(position: 1, imagePath: jpegPath, ocrWords: problemWords);

    Future<pw.Font?> loader() async {
      final data = await File('fonts/IBMPlexMono-Regular.ttf').readAsBytes();
      return pw.Font.ttf(data.buffer.asByteData());
    }

    final builder = PdfBuilder(
      textLayer: const OcrPdfTextLayer(),
      ocrFontLoader: loader,
    );
    final logs = await _capturePrints(() async {
      await builder.build([page], compress: false);
    });
    expect(
      logs.where((l) => l.contains('Unable to find a font')).length,
      0,
      reason: 'PdfBuilder must pass the loaded font down to overlayFor',
    );
  });
}
