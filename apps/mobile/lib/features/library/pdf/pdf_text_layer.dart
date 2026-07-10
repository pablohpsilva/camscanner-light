import 'package:pdf/widgets.dart' as pw;

import '../page_image.dart';

/// Pluggable searchable-text seam. An implementation returns invisible text
/// widgets to Stack over a page's image (OCR injects these in Feature 08); the
/// image-only default returns none, with no change to PdfBuilder when OCR lands.
abstract interface class PdfTextLayer {
  /// [font] is the Unicode font the overlay text is drawn with. Without it,
  /// dart_pdf's default Helvetica (Latin-1 only) strokes a visible .notdef
  /// box-with-X for any glyph it can't encode — see [OcrPdfTextLayer].
  List<pw.Widget> overlayFor(
    PageImage page,
    double width,
    double height, {
    pw.Font? font,
  });
}

/// C1 default: image-only PDFs (no text overlay).
class ImageOnlyTextLayer implements PdfTextLayer {
  const ImageOnlyTextLayer();
  @override
  List<pw.Widget> overlayFor(
    PageImage page,
    double width,
    double height, {
    pw.Font? font,
  }) => const [];
}
