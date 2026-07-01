import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile/features/library/document_file_store.dart';
import 'package:mobile/features/library/drift/app_database.dart';
import 'package:mobile/features/library/drift/drift_document_repository.dart';
import 'package:mobile/features/library/hybrid_warper.dart';
import 'package:mobile/features/library/jpeg_exif_scrubber.dart';
import 'package:mobile/features/library/pdf/pdf_builder.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('searchDocuments matches by page OCR text on device',
      (tester) async {
    final base = await Directory.systemTemp.createTemp('o5dev');
    final db = AppDatabase(NativeDatabase.memory());
    final repo = DriftDocumentRepository(
      db: db,
      scrubber: const JpegExifScrubber(),
      fileStore: DocumentFileStore(base),
      clock: DateTime.now,
      pdfBuilder: const PdfBuilder(),
      warper: const HybridWarper(),
    );

    final now = DateTime.now();
    final id = await db.into(db.documents).insert(DocumentsCompanion.insert(
        name: 'Untitled', createdAt: now, modifiedAt: now));
    await db.into(db.pages).insert(PagesCompanion.insert(
        documentId: id,
        position: 1,
        relativeImagePath: 'documents/$id/page_1.jpg',
        ocrText: const Value('INVOICE 2026 TOTAL DUE')));
    await db.into(db.documents).insert(DocumentsCompanion.insert(
        name: 'Recipe', createdAt: now, modifiedAt: now));

    final hit = await repo.searchDocuments('invoice');
    expect(hit.map((s) => s.document.name), ['Untitled']);
    final miss = await repo.searchDocuments('zzz');
    expect(miss, isEmpty);

    await db.close();
    await base.delete(recursive: true);
  });
}
