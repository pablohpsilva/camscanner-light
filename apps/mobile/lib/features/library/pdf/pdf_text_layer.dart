import 'package:pdf/widgets.dart' as pw;

import '../page_image.dart';

/// Pluggable searchable-text seam. An implementation returns invisible text
/// widgets to Stack over a page's image (OCR injects these in Feature 08); the
/// image-only default returns none, with no change to PdfBuilder when OCR lands.
abstract interface class PdfTextLayer {
  List<pw.Widget> overlayFor(PageImage page, double width, double height);
}

/// C1 default: image-only PDFs (no text overlay).
class ImageOnlyTextLayer implements PdfTextLayer {
  const ImageOnlyTextLayer();
  @override
  List<pw.Widget> overlayFor(PageImage page, double width, double height) =>
      const [];
}
