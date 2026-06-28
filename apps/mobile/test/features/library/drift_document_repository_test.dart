import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document_file_store.dart';
import 'package:mobile/features/library/document_repository.dart';
import 'package:mobile/features/library/drift/app_database.dart';
import 'package:mobile/features/library/drift/drift_document_repository.dart';
import 'package:mobile/features/library/image_metadata_scrubber.dart';
import 'package:mobile/features/library/jpeg_exif_scrubber.dart';
import 'package:mobile/features/library/pdf/pdf_builder.dart';
import 'package:mobile/features/scan/captured_image.dart';

/// A scrubber that throws — to drive the crash-safety rollback test.
class _ThrowingScrubber implements ImageMetadataScrubber {
  @override
  Uint8List scrub(Uint8List bytes) => throw const MetadataScrubException('boom');
}

void main() {
  late Directory base;
  late AppDatabase db;
  late CapturedImage capture;
  // ignore: prefer_function_declarations_over_variables
  final clock = () => DateTime.utc(2026, 6, 27, 20, 26, 42);

  setUp(() {
    base = Directory.systemTemp.createTempSync('b1repo');
    db = AppDatabase(NativeDatabase.memory());
    // a real captured temp file (use the committed EXIF fixture bytes)
    final src = File('${base.path}/cap.jpg')
      ..writeAsBytesSync(File('test/fixtures/exif_sample.jpg').readAsBytesSync());
    capture = CapturedImage(src.path);
  });
  tearDown(() async {
    await db.close();
    if (base.existsSync()) base.deleteSync(recursive: true);
  });

  DriftDocumentRepository repo({ImageMetadataScrubber? scrubber}) =>
      DriftDocumentRepository(
        db: db,
        scrubber: scrubber ?? const JpegExifScrubber(),
        fileStore: DocumentFileStore(base),
        clock: clock,
        pdfBuilder: const PdfBuilder(),
      );

  test('createFromCapture writes a scrubbed JPEG and a document+page row',
      () async {
    final doc = await repo().createFromCapture(capture);

    expect(doc.name, 'Scan 2026-06-27 20.26.42');
    expect(doc.createdAt, DateTime.utc(2026, 6, 27, 20, 26, 42));

    final file = File('${base.path}/documents/${doc.id}/page_1.jpg');
    expect(file.existsSync(), isTrue);
    expect(file.lengthSync(), greaterThan(0));

    final pages = await db.select(db.pages).get();
    expect(pages.single.relativeImagePath, 'documents/${doc.id}/page_1.jpg');
    expect(pages.single.relativeImagePath.startsWith('/'), isFalse,
        reason: 'path MUST be relative, never absolute');
  });

  test('a failed write rolls back — no orphan document row, no dir', () async {
    await expectLater(
      repo(scrubber: _ThrowingScrubber()).createFromCapture(capture),
      throwsA(isA<DocumentSaveException>()),
    );
    expect(await db.select(db.documents).get(), isEmpty,
        reason: 'transaction must roll the row back');
    expect(Directory('${base.path}/documents').existsSync(), isFalse);
  });

  test('listDocumentSummaries reports page count and first-page path',
      () async {
    final doc = await repo().createFromCapture(capture);
    // Add a second page directly (multi-page capture is not built yet).
    await db.into(db.pages).insert(PagesCompanion.insert(
        documentId: doc.id,
        position: 2,
        relativeImagePath: 'documents/${doc.id}/page_2.jpg'));

    final summaries = await repo().listDocumentSummaries();
    expect(summaries, hasLength(1));
    expect(summaries.single.document.id, doc.id);
    expect(summaries.single.pageCount, 2);
    expect(summaries.single.thumbnailPath, startsWith(base.path));
    expect(summaries.single.thumbnailPath,
        endsWith('documents/${doc.id}/page_1.jpg'),
        reason: 'first page is MIN(position) = position 1');
  });

  test('listDocumentSummaries returns newest first', () async {
    final fixture = File('test/fixtures/exif_sample.jpg').readAsBytesSync();
    void seedSource() => File(capture.path).writeAsBytesSync(fixture);

    var t = DateTime.utc(2026, 6, 27, 10);
    final r = DriftDocumentRepository(
      db: db,
      scrubber: const JpegExifScrubber(),
      fileStore: DocumentFileStore(base),
      clock: () => t,
      pdfBuilder: const PdfBuilder(),
    );
    seedSource();
    await r.createFromCapture(capture);
    t = DateTime.utc(2026, 6, 27, 12);
    seedSource();
    await r.createFromCapture(capture);

    final s = await r.listDocumentSummaries();
    expect(s, hasLength(2));
    expect(s.first.document.createdAt.isAfter(s.last.document.createdAt), isTrue);
  });

  test('a document with no page yields pageCount 0 and a null thumbnail',
      () async {
    await db.into(db.documents).insert(DocumentsCompanion.insert(
        name: 'orphan',
        createdAt: DateTime.utc(2026, 1, 1),
        modifiedAt: DateTime.utc(2026, 1, 1)));
    final s = await repo().listDocumentSummaries();
    expect(s.single.pageCount, 0);
    expect(s.single.thumbnailPath, isNull);
  });

  test('getDocumentPages returns pages position-asc with absolute paths',
      () async {
    final doc = await repo().createFromCapture(capture);
    await db.into(db.pages).insert(PagesCompanion.insert(
        documentId: doc.id,
        position: 2,
        relativeImagePath: 'documents/${doc.id}/page_2.jpg'));

    final pages = await repo().getDocumentPages(doc.id);

    expect(pages.map((p) => p.position), [1, 2]);
    expect(pages.first.imagePath, startsWith(base.path));
    expect(pages.first.imagePath, endsWith('documents/${doc.id}/page_1.jpg'));
    expect(pages.first.imagePath.startsWith('/'), isTrue,
        reason: 'viewer needs an absolute path resolved at read time');
  });

  test('getDocumentPages returns empty for a document with no pages', () async {
    final id = await db.into(db.documents).insert(DocumentsCompanion.insert(
        name: 'empty',
        createdAt: DateTime.utc(2026, 1, 1),
        modifiedAt: DateTime.utc(2026, 1, 1)));
    expect(await repo().getDocumentPages(id), isEmpty);
  });

  test('deleteDocument removes the document, its pages, and its on-disk dir',
      () async {
    final doc = await repo().createFromCapture(capture);
    final dir = Directory('${base.path}/documents/${doc.id}');
    expect(dir.existsSync(), isTrue);

    await repo().deleteDocument(doc.id);

    expect(await db.select(db.documents).get(), isEmpty);
    expect(await db.select(db.pages).get(), isEmpty);
    expect(dir.existsSync(), isFalse);
  });

  test('deleteDocument on a non-existent id is a no-op (no throw)', () async {
    await repo().deleteDocument(99999); // never inserted
    expect(await db.select(db.documents).get(), isEmpty);
  });

  test('Tier 1: a delete is durable across a DB close/reopen on disk',
      () async {
    final dir = Directory.systemTemp.createTempSync('b3delpersist');
    final dbFile = File('${dir.path}/camscanner.sqlite');
    final fixture = File('test/fixtures/exif_sample.jpg').readAsBytesSync();
    final src = File('${dir.path}/cap.jpg')..writeAsBytesSync(fixture);

    final db1 = AppDatabase(NativeDatabase(dbFile));
    final repo1 = DriftDocumentRepository(
      db: db1,
      scrubber: const JpegExifScrubber(),
      fileStore: DocumentFileStore(dir),
      clock: () => DateTime.utc(2026, 6, 27, 9),
      pdfBuilder: const PdfBuilder(),
    );
    final saved = await repo1.createFromCapture(CapturedImage(src.path));
    await repo1.deleteDocument(saved.id);
    await db1.close(); // destroy the connection

    final db2 = AppDatabase(NativeDatabase(dbFile)); // brand-new, same file
    final repo2 = DriftDocumentRepository(
      db: db2,
      scrubber: const JpegExifScrubber(),
      fileStore: DocumentFileStore(dir),
      clock: () => DateTime.utc(2026, 6, 27, 9),
      pdfBuilder: const PdfBuilder(),
    );
    final summaries = await repo2.listDocumentSummaries();
    final pages = await repo2.getDocumentPages(saved.id);
    await db2.close();
    final dirGone = !Directory('${dir.path}/documents/${saved.id}').existsSync();
    dir.deleteSync(recursive: true);

    expect(summaries, isEmpty, reason: 'the delete must survive a reopen');
    expect(pages, isEmpty);
    expect(dirGone, isTrue);
  });

  test('Tier 1: documents persist across a DB close/reopen on disk', () async {
    final dir = Directory.systemTemp.createTempSync('b2persist');
    final dbFile = File('${dir.path}/camscanner.sqlite');
    final fixture = File('test/fixtures/exif_sample.jpg').readAsBytesSync();
    final src = File('${dir.path}/cap.jpg')..writeAsBytesSync(fixture);

    final db1 = AppDatabase(NativeDatabase(dbFile));
    final repo1 = DriftDocumentRepository(
      db: db1,
      scrubber: const JpegExifScrubber(),
      fileStore: DocumentFileStore(dir),
      clock: () => DateTime.utc(2026, 6, 27, 9),
      pdfBuilder: const PdfBuilder(),
    );
    final saved = await repo1.createFromCapture(CapturedImage(src.path));
    await db1.close();

    final db2 = AppDatabase(NativeDatabase(dbFile));
    final repo2 = DriftDocumentRepository(
      db: db2,
      scrubber: const JpegExifScrubber(),
      fileStore: DocumentFileStore(dir),
      clock: () => DateTime.utc(2026, 6, 27, 9),
      pdfBuilder: const PdfBuilder(),
    );
    final summaries = await repo2.listDocumentSummaries();
    await db2.close();
    dir.deleteSync(recursive: true);

    expect(summaries, hasLength(1));
    expect(summaries.single.document.id, saved.id);
    expect(summaries.single.pageCount, 1);
    expect(summaries.single.thumbnailPath, endsWith('page_1.jpg'));
  });

  test('exportPdf writes export.pdf and returns a valid PDF file', () async {
    final doc = await repo().createFromCapture(capture);
    final file = await repo().exportPdf(doc.id);

    expect(file.path, endsWith('documents/${doc.id}/export.pdf'));
    expect(file.existsSync(), isTrue);
    final head = file.readAsBytesSync().sublist(0, 4);
    expect(head, [0x25, 0x50, 0x44, 0x46]); // %PDF
  });

  test('exportPdf throws DocumentExportException when the page file is missing',
      () async {
    // Seed a doc + page row, but never write the image file on disk.
    final id = await db.into(db.documents).insert(DocumentsCompanion.insert(
        name: 'noimg',
        createdAt: DateTime.utc(2026, 1, 1),
        modifiedAt: DateTime.utc(2026, 1, 1)));
    await db.into(db.pages).insert(PagesCompanion.insert(
        documentId: id, position: 1, relativeImagePath: 'documents/$id/page_1.jpg'));

    await expectLater(
      repo().exportPdf(id),
      throwsA(isA<DocumentExportException>()),
    );
  });
}
