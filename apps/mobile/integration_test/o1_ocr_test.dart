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
import 'package:mobile/features/library/ocr/ocr_engine.dart';
import 'package:mobile/features/library/ocr/ocr_result.dart';
import 'package:mobile/features/library/pdf/pdf_builder.dart';

class _FixedOcrEngine implements OcrEngine {
  @override
  Future<OcrResult> recognize(Uint8List imageBytes) async =>
      const OcrResult(text: 'ON DEVICE OCR', words: [
        OcrWordBox(text: 'ON', left: .1, top: .1, right: .2, bottom: .2),
      ]);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('runOcr caches recognized text on the real device DB',
      (tester) async {
    final base = await Directory.systemTemp.createTemp('o1dev');
    final db = AppDatabase(NativeDatabase.memory());
    final store = DocumentFileStore(base);
    final repo = DriftDocumentRepository(
      db: db,
      scrubber: const JpegExifScrubber(),
      fileStore: store,
      clock: DateTime.now,
      pdfBuilder: const PdfBuilder(),
      warper: const HybridWarper(), // production warper — not exercised by runOcr
      ocrEngine: _FixedOcrEngine(),
    );

    // Seed a document + page with a real JPEG on disk.
    final now = DateTime.now();
    final docId = await db.into(db.documents).insert(
        DocumentsCompanion.insert(name: 'Doc', createdAt: now, modifiedAt: now));
    final rel = 'documents/$docId/page_1.jpg';
    final jpeg = Uint8List.fromList(
        img.encodeJpg(img.Image(width: 8, height: 8), quality: 90));
    await store.writeRelative(rel, jpeg);
    await db.into(db.pages).insert(PagesCompanion.insert(
        documentId: docId, position: 1, relativeImagePath: rel));

    await repo.runOcr(docId, 1);

    final pages = await repo.getDocumentPages(docId);
    expect(pages.single.ocrText, 'ON DEVICE OCR');

    await db.close();
    await base.delete(recursive: true);
  });
}
