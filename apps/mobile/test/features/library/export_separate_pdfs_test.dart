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
    base = await Directory.systemTemp.createTemp('sep_pdf');
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

  Future<int> seedDoc(String name) async {
    final now = DateTime.now();
    final id = await db
        .into(db.documents)
        .insert(
          DocumentsCompanion.insert(
            name: name,
            createdAt: now,
            modifiedAt: now,
          ),
        );
    final jpeg = Uint8List.fromList(
      img.encodeJpg(img.Image(width: 8, height: 8), quality: 90),
    );
    final rel = 'documents/$id/page_1.jpg';
    await store.writeRelative(rel, jpeg);
    await db
        .into(db.pages)
        .insert(
          PagesCompanion.insert(
            documentId: id,
            position: 1,
            relativeImagePath: rel,
          ),
        );
    return id;
  }

  test('exports one PDF per id, in list order, to temp', () async {
    final a = await seedDoc('Alpha');
    final b = await seedDoc('Beta');

    final files = await repo.exportSeparatePdfs([b, a]); // order preserved

    expect(files.length, 2);
    expect(p.basename(files[0].path), 'Beta.pdf');
    expect(p.basename(files[1].path), 'Alpha.pdf');
    for (final f in files) {
      expect(
        p.isWithin(base.path, f.path),
        isFalse,
        reason: 'exports must not land in the persistent, backed-up store',
      );
      expect(await f.readAsBytes(), isNotEmpty);
    }
  });

  test('throws when documentIds is empty', () async {
    expect(
      () => repo.exportSeparatePdfs(const []),
      throwsA(isA<DocumentExportException>()),
    );
  });

  test('propagates a per-document export failure', () async {
    // A document row with no page file → exportPdf throws → propagates.
    final now = DateTime.now();
    final empty = await db
        .into(db.documents)
        .insert(
          DocumentsCompanion.insert(
            name: 'Empty',
            createdAt: now,
            modifiedAt: now,
          ),
        );
    expect(
      () => repo.exportSeparatePdfs([empty]),
      throwsA(isA<DocumentExportException>()),
    );
  });
}
