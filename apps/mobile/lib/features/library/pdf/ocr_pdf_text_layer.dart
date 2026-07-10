import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../page_image.dart';
import 'pdf_text_layer.dart';

/// Overlays each recognized word as INVISIBLE (but selectable/searchable) text
/// at its box position — the standard searchable-PDF technique. Consumes the
/// page's cached OCR word boxes (normalized 0..1); positions them in PDF points
/// using the page's pixel dimensions.
class OcrPdfTextLayer implements PdfTextLayer {
  const OcrPdfTextLayer();

  @override
  List<pw.Widget> overlayFor(PageImage page, double width, double height) {
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
            fontSize: boxH * 0.8,
            color: PdfColors.black,
            renderingMode: PdfTextRenderingMode.invisible,
          ),
        ),
      );
    }).toList();
  }
}
