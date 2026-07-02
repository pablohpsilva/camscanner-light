import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../export/export_quality.dart';
import '../export/image_compressor.dart';
import '../page_image.dart';
import 'pdf_text_layer.dart';

/// Composes a document's pages into a PDF. Reads each page's JPEG, applies the
/// [compressor] for the chosen [ExportQuality] (Original = verbatim, lossless),
/// and embeds it. The pdf package auto-orients from EXIF; the compressor bakes
/// orientation on re-encode, so alignment holds either way. The default
/// pw.Document() writes no info dict, so the output is metadata-clean.
class PdfBuilder {
  final PdfTextLayer textLayer;
  final ImageCompressor compressor;
  const PdfBuilder({
    this.textLayer = const ImageOnlyTextLayer(),
    this.compressor = const ImageLibraryCompressor(),
  });

  /// [compress] is the PDF-structure deflate flag (tests pass false to grep the
  /// text overlay). [quality] chooses the per-page image re-encode preset.
  Future<Uint8List> build(
    List<PageImage> pages, {
    bool compress = true,
    ExportQuality quality = ExportQuality.original,
  }) async {
    final doc = pw.Document(compress: compress);
    for (final page in pages) {
      final raw = await File(page.displayPath).readAsBytes();
      final bytes = await compressor.compress(raw, quality);
      final image = pw.MemoryImage(bytes); // EXIF auto-orient (baked on re-encode)
      final overlay = textLayer.overlayFor(
          page, image.width!.toDouble(), image.height!.toDouble());
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
