import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:mobile/features/library/document_file_store.dart';
import 'package:mobile/features/library/document_repository.dart';
import 'package:mobile/features/library/drift/app_database.dart';
import 'package:mobile/features/library/drift/drift_document_repository.dart';
import 'package:mobile/features/library/hybrid_warper.dart';
import 'package:mobile/features/library/jpeg_exif_scrubber.dart';
import 'package:mobile/features/library/pdf/pdf_builder.dart';

void main() {
  late AppDatabase db;
  late DriftDocumentRepository repo;
  late DocumentFileStore store;
  late Directory base;

  setUp(() async {
    base = await Directory.systemTemp.createTemp('j1all');
    db = AppDatabase(NativeDatabase.memory());
    store = DocumentFileStore(base);
    repo = DriftDocumentRepository(
      db: db,
      scrubber: const JpegExifScrubber(),
      fileStore: store,
      clock: DateTime.now,
      pdfBuilder: const PdfBuilder(),
      warper: const HybridWarper(),
    );
  });

  tearDown(() async {
    await db.close();
    if (await base.exists()) await base.delete(recursive: true);
  });

  Future<int> seedDoc(int pageCount) async {
    final now = DateTime.now();
    final id = await db
        .into(db.documents)
        .insert(
          DocumentsCompanion.insert(
            name: 'Doc',
            createdAt: now,
            modifiedAt: now,
          ),
        );
    final jpeg = Uint8List.fromList(
      img.encodeJpg(img.Image(width: 8, height: 8), quality: 90),
    );
    for (var pos = 1; pos <= pageCount; pos++) {
      final rel = 'documents/$id/page_$pos.jpg';
      await store.writeRelative(rel, jpeg);
      await db
          .into(db.pages)
          .insert(
            PagesCompanion.insert(
              documentId: id,
              position: pos,
              relativeImagePath: rel,
            ),
          );
    }
    return id;
  }

  test('exports every page as a JPG, in order', () async {
    final id = await seedDoc(2);
    final files = await repo.exportAllPagesAsImages(id);

    expect(files.length, 2);
    // Exports go to the OS temp/cache dir, never the persistent backed-up store.
    for (final f in files) {
      expect(f.path, endsWith('.jpg'));
      expect(
        p.isWithin(base.path, f.path),
        isFalse,
        reason:
            'export must not be written into the persistent, backed-up store',
      );
      final bytes = await f.readAsBytes();
      expect(bytes.sublist(0, 2), [0xFF, 0xD8]); // JPEG magic
    }
  });

  test('throws when the document has no pages', () async {
    final now = DateTime.now();
    final id = await db
        .into(db.documents)
        .insert(
          DocumentsCompanion.insert(
            name: 'Empty',
            createdAt: now,
            modifiedAt: now,
          ),
        );
    expect(
      () => repo.exportAllPagesAsImages(id),
      throwsA(isA<DocumentExportException>()),
    );
  });
}
