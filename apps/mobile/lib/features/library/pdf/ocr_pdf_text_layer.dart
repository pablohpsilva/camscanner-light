import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../page_image.dart';
import 'pdf_text_layer.dart';

/// Loads the bundled Unicode font for the invisible OCR text layer, so dart_pdf
/// can encode non-Latin-1 OCR characters (em-dash, curly quotes, ellipsis, …)
/// instead of stroking a visible .notdef box over the page. Returns null if the
/// asset can't be loaded — the PDF then degrades to the old Latin-1 behaviour
/// rather than failing to export. Wired into [PdfBuilder] as its `ocrFontLoader`.
Future<pw.Font?> loadOcrPdfFont() async {
  try {
    final data = await rootBundle.load('fonts/IBMPlexMono-Regular.ttf');
    return pw.Font.ttf(data);
  } catch (_) {
    return null;
  }
}

/// Overlays each recognized word as INVISIBLE (but selectable/searchable) text
/// at its box position — the standard searchable-PDF technique. Consumes the
/// page's cached OCR word boxes (normalized 0..1); positions them in PDF points
/// using the page's pixel dimensions.
///
/// The text MUST be drawn with a Unicode [font]. dart_pdf's default Helvetica
/// only encodes Latin-1, and for any other character (em-dash, curly quotes,
/// ellipsis, accented/non-Latin letters — all common in OCR output) it strokes
/// a visible .notdef box-with-X as a path OUTSIDE the text object, which the
/// `invisible` text-rendering mode does NOT suppress — so the box appears over
/// the page's letters. A Unicode font resolves those glyphs, so no box is drawn.
class OcrPdfTextLayer implements PdfTextLayer {
  const OcrPdfTextLayer();

  @override
  List<pw.Widget> overlayFor(
    PageImage page,
    double width,
    double height, {
    pw.Font? font,
  }) {
    if (page.ocrWords.isEmpty) return const [];
    return page.ocrWords.where((w) => w.text.trim().isNotEmpty).map((w) {
      final left = (w.left * width).clamp(0.0, width);
      final top = (w.top * height).clamp(0.0, height);
      final boxH = ((w.bottom - w.top) * height).clamp(1.0, height);
      return pw.Positioned(
        left: left,
        top: top,
        child: pw.Text(
          w.text,
          style: pw.TextStyle(
            font: font,
            fontFallback: font == null ? const [] : [font],
            fontSize: boxH * 0.8,
            color: PdfColors.black,
            renderingMode: PdfTextRenderingMode.invisible,
          ),
        ),
      );
    }).toList();
  }
}
