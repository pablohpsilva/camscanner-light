import 'dart:io';
import 'dart:typed_data';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile/features/library/document_file_store.dart';
import 'package:mobile/features/library/drift/app_database.dart';
import 'package:mobile/features/library/drift/drift_document_repository.dart';
import 'package:mobile/features/library/hybrid_warper.dart';
import 'package:mobile/features/library/jpeg_exif_scrubber.dart';
import 'package:mobile/features/library/pdf/pdf_builder.dart';

void main() {
  test('getDocumentPages surfaces rotationQuarterTurns', () async {
    final base = await Directory.systemTemp.createTemp('rot_read');
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
    addTearDown(() async {
      await db.close();
      if (await base.exists()) await base.delete(recursive: true);
    });
    final now = DateTime.now();
    final id = await db
        .into(db.documents)
        .insert(
          DocumentsCompanion.insert(name: 'D', createdAt: now, modifiedAt: now),
        );
    final rel = 'documents/$id/page_1.jpg';
    await store.writeRelative(
      rel,
      Uint8List.fromList(img.encodeJpg(img.Image(width: 20, height: 10))),
    );
    await db
        .into(db.pages)
        .insert(
          PagesCompanion.insert(
            documentId: id,
            position: 1,
            relativeImagePath: rel,
            rotationQuarterTurns: const Value(2),
          ),
        );
    final page = (await repo.getDocumentPages(id)).single;
    expect(page.rotationQuarterTurns, 2);
  });
}
