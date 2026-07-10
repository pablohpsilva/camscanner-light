import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:mobile/features/library/document_file_store.dart';
import 'package:mobile/features/library/drift/app_database.dart';
import 'package:mobile/features/library/drift/drift_document_repository.dart';
import 'package:mobile/features/library/hybrid_warper.dart';
import 'package:mobile/features/library/jpeg_exif_scrubber.dart';
import 'package:mobile/features/library/ocr/mlkit_ocr_engine.dart';
import 'package:mobile/features/library/pdf/ocr_pdf_text_layer.dart';
import 'package:mobile/features/library/pdf/pdf_builder.dart';
import 'package:mobile/features/scan/captured_image.dart';

String _dec(List<int> bytes) {
  final b = StringBuffer();
  for (final c in bytes) {
    b.writeCharCode(c);
  }
  return b.toString();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('scanned text becomes selectable text in the exported PDF', (
    tester,
  ) async {
    final base = await Directory.systemTemp.createTemp('ocre2e');
    final db = AppDatabase(NativeDatabase.memory());
    final repo = DriftDocumentRepository(
      db: db,
      scrubber: const JpegExifScrubber(),
      fileStore: DocumentFileStore(base),
      clock: DateTime.now,
      pdfBuilder: const PdfBuilder(textLayer: OcrPdfTextLayer()),
      warper: const HybridWarper(),
      ocrEngine: const MlKitOcrEngine(),
    );

    // A "scanned" page: black text on white.
    final image = img.Image(width: 720, height: 220);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    img.drawString(
      image,
      'HELLO WORLD',
      font: img.arial48,
      x: 40,
      y: 80,
      color: img.ColorRgb8(0, 0, 0),
    );
    final capFile = File('${base.path}/cap.jpg')
      ..writeAsBytesSync(Uint8List.fromList(img.encodeJpg(image, quality: 95)));

    final doc = await repo.createFromCapture(CapturedImage(capFile.path));
    // Deterministically run OCR (production also auto-runs it fire-and-forget).
    await repo.runOcr(doc.id, 1);

    final pages = await repo.getDocumentPages(doc.id);
    // ignore: avoid_print
    print(
      'E2E ocrText="${pages.single.ocrText}" words=${pages.single.ocrWords.length}',
    );
    expect(pages.single.ocrText!.toUpperCase(), contains('HELLO'));

    // Build uncompressed to prove the recognized text is EMBEDDED as invisible
    // (selectable) text. The production exportPdf compresses the content stream,
    // so the text isn't greppable in the raw bytes — but it's the same text and
    // is selectable in any PDF viewer.
    final pdfBytes = await const PdfBuilder(
      textLayer: OcrPdfTextLayer(),
    ).build(pages, compress: false);
    final pdfText = _dec(pdfBytes).toUpperCase();
    expect(
      pdfText.contains('HELLO'),
      isTrue,
      reason:
          'PDF must carry the recognized text as an invisible selectable layer',
    );
    expect(pdfText.contains('WORLD'), isTrue);

    // The production export produces a valid PDF file from the OCR'd page.
    final pdfFile = await repo.exportPdf(doc.id);
    expect(_dec(pdfFile.readAsBytesSync().sublist(0, 4)), '%PDF');

    await db.close();
    await base.delete(recursive: true);
  });
}
