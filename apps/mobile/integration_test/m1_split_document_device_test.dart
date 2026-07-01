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
import 'package:mobile/features/library/pdf/pdf_builder.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('splitAfter moves trailing pages to a new document on device',
      (tester) async {
    final base = await Directory.systemTemp.createTemp('m1dev');
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

    final jpeg = Uint8List.fromList(
        img.encodeJpg(img.Image(width: 8, height: 8), quality: 90));
    final now = DateTime.now();
    final id = await db.into(db.documents).insert(DocumentsCompanion.insert(
        name: 'Doc', createdAt: now, modifiedAt: now));
    for (var p = 1; p <= 3; p++) {
      final rel = 'documents/$id/page_$p.jpg';
      await store.writeRelative(rel, jpeg);
      await db.into(db.pages).insert(PagesCompanion.insert(
          documentId: id, position: p, relativeImagePath: rel));
    }

    final created = await repo.splitAfter(id, 1);
    expect((await repo.getDocumentPages(id)).length, 1);
    expect((await repo.getDocumentPages(created.id)).length, 2);

    await db.close();
    await base.delete(recursive: true);
  });
}
