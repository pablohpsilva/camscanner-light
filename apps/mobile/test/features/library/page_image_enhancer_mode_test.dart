import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile/features/library/document_file_store.dart';
import 'package:mobile/features/library/drift/app_database.dart';
import 'package:mobile/features/library/drift/drift_document_repository.dart';
import 'package:mobile/features/library/enhancer_mode.dart';
import 'package:mobile/features/library/hybrid_warper.dart';
import 'package:mobile/features/library/jpeg_exif_scrubber.dart';
import 'package:mobile/features/library/pdf/pdf_builder.dart';

void main() {
  test('getDocumentPages surfaces the stored enhancerMode', () async {
    final base = await Directory.systemTemp.createTemp('pimode');
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
    final id = await db.into(db.documents).insert(
          DocumentsCompanion.insert(name: 'D', createdAt: now, modifiedAt: now),
        );
    await store.writeRelative(
      'documents/$id/page_1.jpg',
      Uint8List.fromList(img.encodeJpg(img.Image(width: 10, height: 10))),
    );
    await db.into(db.pages).insert(
          PagesCompanion.insert(
            documentId: id,
            position: 1,
            relativeImagePath: 'documents/$id/page_1.jpg',
            enhancerMode: const Value(2), // auto
          ),
        );

    final pages = await repo.getDocumentPages(id);
    expect(pages.single.enhancerMode, EnhancerMode.auto);

    await db.close();
    await base.delete(recursive: true);
  });
}
