import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../page_image.dart';
import 'pdf_text_layer.dart';

/// Composes a document's pages into a PDF. Pure: reads each page's JPEG from
/// disk and returns the PDF bytes. The JPEG is embedded LOSSLESSLY
/// (/DCTDecode, verbatim) and auto-oriented from its EXIF tag by the pdf
/// package — so there is no manual orientation code here. The default
/// pw.Document() writes no info dict, so the output is metadata-clean.
class PdfBuilder {
  final PdfTextLayer textLayer;
  const PdfBuilder({this.textLayer = const ImageOnlyTextLayer()});

  /// [compress] is true in production; tests pass false to grep the (otherwise
  /// deflated) text overlay.
  Future<Uint8List> build(List<PageImage> pages, {bool compress = true}) async {
    final doc = pw.Document(compress: compress);
    for (final page in pages) {
      final bytes = await File(page.displayPath).readAsBytes();
      final image = pw.MemoryImage(bytes); // lossless + EXIF auto-orient
      final overlay = textLayer.overlayFor(page);
      doc.addPage(
        pw.Page(
          pageFormat:
              PdfPageFormat(image.width!.toDouble(), image.height!.toDouble()),
          build: (context) => pw.Stack(children: [pw.Image(image), ...overlay]),
        ),
      );
    }
    return doc.save();
  }
}
