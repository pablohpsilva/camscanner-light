import 'dart:convert'; // latin1
import 'dart:io';
import 'dart:typed_data';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/library/image_enhancer.dart';
import 'package:mobile/features/library/document_file_store.dart';
import 'package:mobile/features/library/document_repository.dart';
import 'package:mobile/features/library/drift/app_database.dart';
import 'package:mobile/features/library/drift/drift_document_repository.dart';
import 'package:mobile/features/library/image_metadata_scrubber.dart';
import 'package:mobile/features/library/image_warper.dart';
import 'package:mobile/features/library/jpeg_exif_scrubber.dart';
import 'package:mobile/features/library/pdf/pdf_builder.dart';
import 'package:mobile/features/scan/captured_image.dart';

import '../../support/fake_library.dart';

/// A scrubber that throws — to drive the crash-safety rollback test.
class _ThrowingScrubber implements ImageMetadataScrubber {
  @override
  Uint8List scrub(Uint8List bytes) => throw const MetadataScrubException('boom');
}

/// Records enhance() calls for assertions; returns bytes unchanged.
class _RecordingEnhancer implements ImageEnhancer {
  int calls = 0;

  @override
  Future<Uint8List> enhance(Uint8List bytes) async {
    calls++;
    return bytes;
  }
}

/// Always throws — tests that enhancement failure is silent.
class _ThrowingEnhancer implements ImageEnhancer {
  const _ThrowingEnhancer();

  @override
  Future<Uint8List> enhance(Uint8List bytes) async =>
      throw Exception('enhance failed');
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

  DriftDocumentRepository repo({
    ImageMetadataScrubber? scrubber,
    ImageWarper? warper,
  }) =>
      DriftDocumentRepository(
        db: db,
        scrubber: scrubber ?? const JpegExifScrubber(),
        fileStore: DocumentFileStore(base),
        clock: clock,
        pdfBuilder: const PdfBuilder(),
        warper: warper ?? FakeImageWarper(),
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
      warper: FakeImageWarper(),
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
      warper: FakeImageWarper(),
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
      warper: FakeImageWarper(),
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
      warper: FakeImageWarper(),
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
      warper: FakeImageWarper(),
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

  test('exportPdf writes one PDF page per document page (3-page doc)', () async {
    final r = repo();
    final doc = await r.createFromCapture(capture); // page 1
    Uint8List fixture() =>
        File('test/fixtures/exif_sample.jpg').readAsBytesSync();
    CapturedImage cap(String name) => CapturedImage(
        (File('${base.path}/$name.jpg')..writeAsBytesSync(fixture())).path);
    await r.addPageToDocument(doc.id, cap('c2')); // page 2
    await r.addPageToDocument(doc.id, cap('c3')); // page 3

    final file = await r.exportPdf(doc.id);
    final s = latin1.decode(file.readAsBytesSync(), allowInvalid: true);
    expect(RegExp(r'/Type\s*/Page(?![s])').allMatches(s).length, 3,
        reason: 'exportPdf passes ALL pages, not just the first');
  });

  test('rename updates the name and bumps modifiedAt; createdAt unchanged',
      () async {
    // The shared repo() helper uses a FIXED clock, which cannot show a bump.
    // Use the advancing-clock pattern (as 'listDocumentSummaries returns newest
    // first' does): create at T1, rename at T2.
    var t = DateTime.utc(2026, 6, 27, 10);
    final r = DriftDocumentRepository(
      db: db,
      scrubber: const JpegExifScrubber(),
      fileStore: DocumentFileStore(base),
      clock: () => t,
      pdfBuilder: const PdfBuilder(),
      warper: FakeImageWarper(),
    );
    final doc = await r.createFromCapture(capture);
    t = DateTime.utc(2026, 6, 27, 12); // clock advances before the rename

    final renamed = await r.rename(doc.id, 'Tax 2026');

    expect(renamed.name, 'Tax 2026');
    expect(renamed.createdAt, DateTime.utc(2026, 6, 27, 10));
    expect(renamed.modifiedAt, DateTime.utc(2026, 6, 27, 12),
        reason: 'rename bumps modifiedAt to the clock at rename time');

    final row = await (db.select(db.documents)
          ..where((d) => d.id.equals(doc.id)))
        .getSingle();
    expect(row.name, 'Tax 2026', reason: 'the new name is persisted');
    expect(row.modifiedAt, DateTime.utc(2026, 6, 27, 12));
  });

  test('rename trims surrounding whitespace', () async {
    final doc = await repo().createFromCapture(capture);
    final renamed = await repo().rename(doc.id, '   Spaced Name   ');
    expect(renamed.name, 'Spaced Name');
  });

  test('rename throws DocumentRenameException on an empty/whitespace name',
      () async {
    final doc = await repo().createFromCapture(capture);
    await expectLater(
      repo().rename(doc.id, '   '),
      throwsA(isA<DocumentRenameException>()),
    );
  });

  test('rename throws DocumentRenameException for a non-existent id', () async {
    await expectLater(
      repo().rename(99999, 'Whatever'),
      throwsA(isA<DocumentRenameException>()),
    );
  });

  test('createFromCapture persists the given corners; getDocumentPages reads them back',
      () async {
    const corners = CropCorners(
      topLeft: Offset(0.1, 0.1), topRight: Offset(0.9, 0.12),
      bottomRight: Offset(0.88, 0.9), bottomLeft: Offset(0.08, 0.92));
    final doc = await repo().createFromCapture(capture, corners: corners);
    final pages = await repo().getDocumentPages(doc.id);
    expect(pages.single.corners, corners);
  });

  test('createFromCapture with no corners reads back fullFrame', () async {
    final doc = await repo().createFromCapture(capture);
    final pages = await repo().getDocumentPages(doc.id);
    expect(pages.single.corners, CropCorners.fullFrame);
  });

  group('E2 — warp on save', () {
    test('non-full-frame corners: flatRelativePath written and round-trips', () async {
      final fakeBytes = Uint8List.fromList([0xFF, 0xD8, 0x01]); // fake JPEG marker
      final warper = FakeImageWarper(returnValue: fakeBytes);
      const corners = CropCorners(
        topLeft: Offset(0.1, 0.1),
        topRight: Offset(0.9, 0.1),
        bottomRight: Offset(0.9, 0.9),
        bottomLeft: Offset(0.1, 0.9),
      );

      final doc = await repo(warper: warper).createFromCapture(capture,
          corners: corners);

      // Warper was called once.
      expect(warper.calls, 1);

      // Flat file exists on disk.
      final flatFile =
          File('${base.path}/documents/${doc.id}/page_1_flat.jpg');
      expect(flatFile.existsSync(), isTrue);
      expect(flatFile.readAsBytesSync(), fakeBytes);

      // getDocumentPages round-trips flatImagePath.
      final pages = await repo(warper: warper).getDocumentPages(doc.id);
      expect(pages.single.flatImagePath, flatFile.path);
      expect(pages.single.displayPath, flatFile.path);
    });

    test('full-frame corners: flatRelativePath stays null', () async {
      final warper = FakeImageWarper();
      final doc = await repo(warper: warper).createFromCapture(capture,
          corners: CropCorners.fullFrame);
      expect(warper.calls, 0); // short-circuited before calling warper

      final pages = await repo(warper: warper).getDocumentPages(doc.id);
      expect(pages.single.flatImagePath, isNull);
      expect(pages.single.displayPath, pages.single.imagePath);
    });

    test('null corners (unset): flatRelativePath stays null', () async {
      final warper = FakeImageWarper();
      final doc = await repo(warper: warper).createFromCapture(capture);
      expect(warper.calls, 0);

      final pages = await repo(warper: warper).getDocumentPages(doc.id);
      expect(pages.single.flatImagePath, isNull);
    });

    test('warper throws WarpException: save still succeeds, flatRelativePath null',
        () async {
      final warper = FakeImageWarper(throws: true);
      const corners = CropCorners(
        topLeft: Offset(0.1, 0.1),
        topRight: Offset(0.9, 0.1),
        bottomRight: Offset(0.9, 0.9),
        bottomLeft: Offset(0.1, 0.9),
      );

      final doc = await repo(warper: warper).createFromCapture(capture,
          corners: corners);
      expect(doc.id, greaterThan(0));

      final pages = await repo(warper: warper).getDocumentPages(doc.id);
      expect(pages.single.flatImagePath, isNull);
      // Original file still written.
      final origFile =
          File('${base.path}/documents/${doc.id}/page_1.jpg');
      expect(origFile.existsSync(), isTrue);
    });

    test('listDocumentSummaries: thumbnailPath prefers flat path', () async {
      final fakeBytes = Uint8List.fromList([0xFF, 0xD8, 0x02]);
      final warper = FakeImageWarper(returnValue: fakeBytes);
      const corners = CropCorners(
        topLeft: Offset(0.1, 0.1),
        topRight: Offset(0.9, 0.1),
        bottomRight: Offset(0.9, 0.9),
        bottomLeft: Offset(0.1, 0.9),
      );
      final doc = await repo(warper: warper).createFromCapture(capture,
          corners: corners);

      final summaries =
          await repo(warper: warper).listDocumentSummaries();
      final flatPath =
          '${base.path}/documents/${doc.id}/page_1_flat.jpg';
      expect(summaries.single.thumbnailPath, flatPath);
    });
  });

  group('E3 — updatePageCorners', () {
    test('non-fullFrame corners: flat written to disk and DB updated', () async {
      final fakeFlat = Uint8List.fromList([0xFF, 0xD8, 0x03]);
      // Create document with NO flat (no corners → full-frame, so warp is skipped).
      final doc = await repo().createFromCapture(capture);
      final before = await repo().getDocumentPages(doc.id);
      expect(before.single.flatImagePath, isNull);

      const newCorners = CropCorners(
        topLeft: Offset(0.05, 0.05),
        topRight: Offset(0.95, 0.05),
        bottomRight: Offset(0.95, 0.95),
        bottomLeft: Offset(0.05, 0.95),
      );
      await repo(warper: FakeImageWarper(returnValue: fakeFlat))
          .updatePageCorners(doc.id, 1, newCorners);

      final flatFile =
          File('${base.path}/documents/${doc.id}/page_1_flat.jpg');
      expect(flatFile.existsSync(), isTrue);
      expect(flatFile.readAsBytesSync(), fakeFlat);

      final after = await repo().getDocumentPages(doc.id);
      expect(after.single.flatImagePath, flatFile.path);
      expect(after.single.corners, newCorners);
    });

    test('fullFrame corners: flat file deleted and DB cleared', () async {
      final fakeFlat = Uint8List.fromList([0xFF, 0xD8, 0x04]);
      const initCorners = CropCorners(
        topLeft: Offset(0.1, 0.1),
        topRight: Offset(0.9, 0.1),
        bottomRight: Offset(0.9, 0.9),
        bottomLeft: Offset(0.1, 0.9),
      );
      // Create document WITH a flat.
      final doc = await repo(warper: FakeImageWarper(returnValue: fakeFlat))
          .createFromCapture(capture, corners: initCorners);
      final flatFile =
          File('${base.path}/documents/${doc.id}/page_1_flat.jpg');
      expect(flatFile.existsSync(), isTrue, reason: 'pre-condition: flat exists');

      // Re-edit to fullFrame.
      await repo().updatePageCorners(doc.id, 1, CropCorners.fullFrame);

      expect(flatFile.existsSync(), isFalse,
          reason: 'flat file must be deleted on fullFrame reset');
      final after = await repo().getDocumentPages(doc.id);
      expect(after.single.flatImagePath, isNull);
      expect(after.single.corners, CropCorners.fullFrame);
    });

    test('warp throws: method rethrows and DB is unchanged', () async {
      final doc = await repo().createFromCapture(capture);
      const badCorners = CropCorners(
        topLeft: Offset(0.1, 0.1),
        topRight: Offset(0.9, 0.1),
        bottomRight: Offset(0.9, 0.9),
        bottomLeft: Offset(0.1, 0.9),
      );

      await expectLater(
        repo(warper: FakeImageWarper(throws: true))
            .updatePageCorners(doc.id, 1, badCorners),
        throwsA(isA<WarpException>()),
      );

      // DB must remain unchanged: no flatRelativePath set.
      final after = await repo().getDocumentPages(doc.id);
      expect(after.single.flatImagePath, isNull,
          reason: 'rethrow must not update DB');
    });

    test('unknown page: throws DocumentSaveException', () async {
      await expectLater(
        repo().updatePageCorners(99999, 1, CropCorners.fullFrame),
        throwsA(isA<DocumentSaveException>()),
      );
    });
  });

  const testCorners = CropCorners(
    topLeft: Offset(0.1, 0.1),
    topRight: Offset(0.9, 0.1),
    bottomRight: Offset(0.9, 0.9),
    bottomLeft: Offset(0.1, 0.9),
  );

  test(
      'createFromCapture applies enhancer to flat bytes on cropped capture',
      () async {
    final enhancer = _RecordingEnhancer();
    // FakeImageWarper with a non-null returnValue simulates a successful warp.
    final r = repo(warper: FakeImageWarper(returnValue: Uint8List.fromList([1, 2, 3])));
    await r.createFromCapture(capture,
        corners: testCorners, enhancer: enhancer);
    expect(enhancer.calls, 1,
        reason: 'enhancer must be called once on the flat bytes');
  });

  test(
      'createFromCapture applies enhancer to original bytes on full-frame capture',
      () async {
    final enhancer = _RecordingEnhancer();
    // No corners → full-frame path; warp is skipped regardless of FakeImageWarper's return value.
    final r = repo(warper: FakeImageWarper());
    await r.createFromCapture(capture, enhancer: enhancer);
    expect(enhancer.calls, 1,
        reason: 'enhancer must be called once on the scrubbed original');
  });

  test('createFromCapture proceeds silently when enhancer throws', () async {
    final r = repo(
        warper: FakeImageWarper(returnValue: Uint8List.fromList([1, 2, 3])));
    await expectLater(
      r.createFromCapture(capture,
          corners: testCorners, enhancer: const _ThrowingEnhancer()),
      completes,
      reason: 'enhancement failure must not abort the save',
    );
  });

  group('reorderPages', () {
    test('swaps page positions for a 2-page document', () async {
      final r = repo();
      final doc = await r.createFromCapture(capture);
      // Add a second page using the same fixture file.
      final src2 = File('${base.path}/cap2.jpg')
        ..writeAsBytesSync(
            File('test/fixtures/exif_sample.jpg').readAsBytesSync());
      await r.addPageToDocument(doc.id, CapturedImage(src2.path));

      final before = await r.getDocumentPages(doc.id);
      expect(before.map((p) => p.position), [1, 2]);
      final path1 = before[0].imagePath;
      final path2 = before[1].imagePath;

      // Swap: position 2 goes first, position 1 goes second.
      await r.reorderPages(doc.id, [2, 1]);

      final after = await r.getDocumentPages(doc.id);
      expect(after[0].imagePath, path2,
          reason: 'former page 2 is now at index 0');
      expect(after[1].imagePath, path1,
          reason: 'former page 1 is now at index 1');
    });

    test('throws DocumentSaveException when documentId has no pages', () async {
      await expectLater(
        repo().reorderPages(9999, [1]),
        throwsA(isA<DocumentSaveException>()),
      );
    });
  });
}
