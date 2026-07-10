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

  /// Loads the Unicode font for the searchable text overlay. Called once per
  /// build; null (or a null result) keeps dart_pdf's Latin-1 default. Injected
  /// so the pure builder never touches the asset bundle directly.
  final Future<pw.Font?> Function()? ocrFontLoader;

  const PdfBuilder({
    this.textLayer = const ImageOnlyTextLayer(),
    this.compressor = const ImageLibraryCompressor(),
    this.ocrFontLoader,
  });

  /// [compress] is the PDF-structure deflate flag (tests pass false to grep the
  /// text overlay). [quality] chooses the per-page image re-encode preset.
  /// [idCardLayout] emits ONE portrait-A4 page with all images centered and
  /// vertically stacked (front top, back bottom), aspect-ratio preserved.
  Future<Uint8List> build(
    List<PageImage> pages, {
    bool compress = true,
    ExportQuality quality = ExportQuality.original,
    bool idCardLayout = false,
  }) async {
    final doc = pw.Document(compress: compress);
    if (idCardLayout && pages.isNotEmpty) {
      final images = <pw.MemoryImage>[];
      for (final page in pages) {
        final raw = await File(page.displayPath).readAsBytes();
        final bytes = await compressor.compress(raw, quality);
        images.add(pw.MemoryImage(bytes));
      }
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          build: (context) => pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              for (var i = 0; i < images.length; i++) ...[
                if (i > 0) pw.SizedBox(height: 24),
                pw.Expanded(child: pw.Image(images[i], fit: pw.BoxFit.contain)),
              ],
            ],
          ),
        ),
      );
      return doc.save();
    }
    // Loaded once (not per page) — the overlay font is shared across pages.
    final ocrFont = ocrFontLoader == null ? null : await ocrFontLoader!.call();
    for (final page in pages) {
      final raw = await File(page.displayPath).readAsBytes();
      final bytes = await compressor.compress(raw, quality);
      final image = pw.MemoryImage(
        bytes,
      ); // EXIF auto-orient (baked on re-encode)
      final overlay = textLayer.overlayFor(
        page,
        image.width!.toDouble(),
        image.height!.toDouble(),
        font: ocrFont,
      );
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(
            image.width!.toDouble(),
            image.height!.toDouble(),
          ),
          build: (context) => pw.Stack(children: [pw.Image(image), ...overlay]),
        ),
      );
    }
    return doc.save();
  }
}
