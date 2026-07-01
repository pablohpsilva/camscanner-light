import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:mobile/features/library/document_file_store.dart';
import 'package:mobile/features/library/drift/app_database.dart';
import 'package:mobile/features/library/drift/drift_document_repository.dart';
import 'package:mobile/features/library/hybrid_warper.dart';
import 'package:mobile/features/library/jpeg_exif_scrubber.dart';
import 'package:mobile/features/library/ocr/ocr_result.dart';
import 'package:mobile/features/library/pdf/pdf_builder.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('rotatePage swaps image dims and rotates boxes on device',
      (tester) async {
    final base = await Directory.systemTemp.createTemp('k1dev');
    final db = AppDatabase(NativeDatabase.memory());
    final store = DocumentFileStore(base);
    final repo = DriftDocumentRepository(
      db: db,
      scrubber: const JpegExifScrubber(),
      fileStore: store,
      clock: DateTime.now,
      pdfBuilder: const PdfBuilder(),
      warper: const HybridWarper(),
    );

    final now = DateTime.now();
    final id = await db.into(db.documents).insert(DocumentsCompanion.insert(
        name: 'Doc', createdAt: now, modifiedAt: now));
    final jpeg = Uint8List.fromList(
        img.encodeJpg(img.Image(width: 40, height: 20), quality: 95));
    final rel = 'documents/$id/page_1.jpg';
    await store.writeRelative(rel, jpeg);
    const box = OcrWordBox(text: 'hi', left: 0.0, top: 0.0, right: 0.2, bottom: 0.1);
    await db.into(db.pages).insert(PagesCompanion.insert(
          documentId: id,
          position: 1,
          relativeImagePath: rel,
          ocrBoxes: Value(const OcrResult(text: 'hi', words: [box]).encodeBoxes()),
        ));

    await repo.rotatePage(id, 1);

    final page = (await repo.getDocumentPages(id)).single;
    final decoded = img.decodeImage(File(page.flatImagePath!).readAsBytesSync())!;
    expect(decoded.width, 20);
    expect(decoded.height, 40);
    expect(page.ocrWords.single.left, closeTo(0.9, 1e-6));

    await db.close();
    await base.delete(recursive: true);
  });
}
