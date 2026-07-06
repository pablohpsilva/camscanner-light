import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
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
    base = await Directory.systemTemp.createTemp('separate');
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

  Uint8List jpeg() =>
      Uint8List.fromList(img.encodeJpg(img.Image(width: 8, height: 8), quality: 90));

  Future<int> seedDoc(String name) async {
    final now = DateTime.now();
    final id = await db.into(db.documents).insert(
        DocumentsCompanion.insert(name: name, createdAt: now, modifiedAt: now));
    final rel = 'documents/$id/page_1.jpg';
    await store.writeRelative(rel, jpeg());
    await db.into(db.pages).insert(PagesCompanion.insert(
        documentId: id,
        position: 1,
        relativeImagePath: rel,
        flatRelativePath: const Value(null)));
    return id;
  }

  test('returns one PDF file per document in list order', () async {
    final a = await seedDoc('Report');
    final b = await seedDoc('Invoice');

    final files = await repo.exportSeparatePdfs([a, b]);

    expect(files.length, 2);
    expect(files[0].path, endsWith('Report.pdf'));
    expect(files[1].path, endsWith('Invoice.pdf'));
    for (final f in files) {
      expect(await f.exists(), isTrue);
      expect(f.path.startsWith(Directory.systemTemp.path), isTrue);
    }
  });

  test('throws on an empty document list', () async {
    expect(() => repo.exportSeparatePdfs(const []),
        throwsA(isA<DocumentExportException>()));
  });
}
