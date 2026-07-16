import 'dart:io';
import 'dart:typed_data';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/library/document_file_store.dart';
import 'package:mobile/features/library/document_repository.dart';
import 'package:mobile/features/library/drift/app_database.dart';
import 'package:mobile/features/library/drift/drift_document_repository.dart';
import 'package:mobile/features/library/export/document_exporter.dart';
import 'package:mobile/features/library/image_metadata_scrubber.dart';
import 'package:mobile/features/library/jpeg_exif_scrubber.dart';
import 'package:mobile/features/library/ocr/ocr_engine.dart';
import 'package:mobile/features/library/ocr/ocr_result.dart';
import 'package:mobile/features/library/pdf/pdf_builder.dart';
import 'package:mobile/features/library/pdf/pdf_encryptor.dart';
import 'package:mobile/features/scan/captured_image.dart';

import '../../support/fake_library.dart';

/// An [OcrEngine] that always throws — drives the fire-and-forget
/// `_triggerOcr` swallow path (drift_document_repository.dart:1181).
class _ThrowingOcrEngine implements OcrEngine {
  const _ThrowingOcrEngine();
  @override
  Future<OcrResult> recognize(Uint8List imageBytes) async =>
      throw Exception('ocr boom');
}

/// A scrubber that always throws [MetadataScrubException] (NOT a
/// [DocumentSaveException]) — drives the generic-exception wrap branches in
/// addPageToDocument/replacePage's catch blocks (lines 844, 967), as opposed
/// to their DocumentSaveException-rethrow branches.
class _ThrowingScrubber implements ImageMetadataScrubber {
  const _ThrowingScrubber();
  @override
  Uint8List scrub(Uint8List bytes) =>
      throw const MetadataScrubException('boom');
}

/// A [PdfEncryptor] that throws a [DocumentExportException] directly — drives
/// the `if (e is DocumentExportException) rethrow` branch in
/// exportProtectedPdf's catch block (line 442-443), as opposed to the
/// generic-exception wrap branch below it.
class _ThrowingDocumentExportEncryptor implements PdfEncryptor {
  const _ThrowingDocumentExportEncryptor();
  @override
  Future<Uint8List> encrypt(Uint8List pdfBytes, String password) async =>
      throw const DocumentExportException('encryptor boom');
}

/// A scrubber that throws [DocumentExportException] directly — drives the
/// `if (e is DocumentExportException) rethrow` branch in exportPageAsImage's
/// catch block (line 495-496).
class _ThrowingDocumentExportScrubber implements ImageMetadataScrubber {
  const _ThrowingDocumentExportScrubber();
  @override
  Uint8List scrub(Uint8List bytes) =>
      throw const DocumentExportException('scrub boom');
}

void main() {
  late Directory base;
  late AppDatabase db;
  late CapturedImage capture;
  // ignore: prefer_function_declarations_over_variables
  final clock = () => DateTime.utc(2026, 6, 27, 20, 26, 42);

  setUp(() {
    base = Directory.systemTemp.createTempSync('b1repoextra');
    db = AppDatabase(NativeDatabase.memory());
    final src = File('${base.path}/cap.jpg')
      ..writeAsBytesSync(
        File('test/fixtures/exif_sample.jpg').readAsBytesSync(),
      );
    capture = CapturedImage(src.path);
  });
  tearDown(() async {
    await db.close();
    if (base.existsSync()) base.deleteSync(recursive: true);
  });

  DriftDocumentRepository repo({
    OcrEngine ocrEngine = const NoOpOcrEngine(),
    ImageMetadataScrubber scrubber = const JpegExifScrubber(),
    PdfEncryptor encryptor = const SyncfusionPdfEncryptor(),
  }) {
    final fileStore = DocumentFileStore(base);
    return DriftDocumentRepository(
      db: db,
      scrubber: scrubber,
      fileStore: fileStore,
      clock: clock,
      pdfBuilder: const PdfBuilder(),
      warper: FakeImageWarper(),
      ocrEngine: ocrEngine,
      // The exporter now holds the encryptor (P05 T05.4/SOLID-02).
      exporter: DocumentExporter(
        db: db,
        fileStore: fileStore,
        pdfBuilder: const PdfBuilder(),
        scrubber: scrubber,
        encryptor: encryptor,
      ),
    );
  }

  Future<int> seedEmptyDocument(String name) => db
      .into(db.documents)
      .insert(
        DocumentsCompanion.insert(
          name: name,
          createdAt: DateTime.utc(2026, 1, 1),
          modifiedAt: DateTime.utc(2026, 1, 1),
        ),
      );

  group('exportCombinedPdf — DocumentExportException passthrough', () {
    test(
      'documentIds non-empty but every document has zero pages: rethrows '
      'the "no pages" DocumentExportException untouched (not re-wrapped)',
      () async {
        final id = await seedEmptyDocument('orphan');
        await expectLater(
          repo().exportCombinedPdf([id]),
          throwsA(
            isA<DocumentExportException>().having(
              (e) => e.message,
              'message',
              'combined export failed: no pages',
            ),
          ),
        );
      },
    );
  });

  group('exportProtectedPdf — DocumentExportException passthrough', () {
    test(
      'a page whose image file is missing on disk: rethrows the original '
      'DocumentExportException from pdf building, not a re-wrapped one',
      () async {
        final id = await seedEmptyDocument('noimg');
        await db
            .into(db.pages)
            .insert(
              PagesCompanion.insert(
                documentId: id,
                position: 1,
                relativeImagePath: 'documents/$id/page_1.jpg',
              ),
            );
        await expectLater(
          repo().exportProtectedPdf(id, 'pw'),
          throwsA(
            isA<DocumentExportException>().having(
              (e) => e.message,
              'message',
              startsWith('protect failed:'),
            ),
          ),
        );
      },
    );

    test('the encryptor itself throws a DocumentExportException: it is '
        'rethrown UNCHANGED (message preserved), not re-wrapped as '
        '"protect failed: ..."', () async {
      final doc = await repo().createFromCapture(capture);
      await expectLater(
        repo(
          encryptor: const _ThrowingDocumentExportEncryptor(),
        ).exportProtectedPdf(doc.id, 'pw'),
        throwsA(
          isA<DocumentExportException>().having(
            (e) => e.message,
            'message',
            'encryptor boom',
          ),
        ),
      );
    });
  });

  group('exportPageAsImage — DocumentExportException passthrough', () {
    test(
      'the page row exists but its image file is missing on disk: throws '
      'DocumentExportException (read failure wrapped, not a no-page error)',
      () async {
        final id = await seedEmptyDocument('noimg2');
        await db
            .into(db.pages)
            .insert(
              PagesCompanion.insert(
                documentId: id,
                position: 1,
                relativeImagePath: 'documents/$id/page_1.jpg',
              ),
            );
        await expectLater(
          repo().exportPageAsImage(id, 1),
          throwsA(
            isA<DocumentExportException>().having(
              (e) => e.message,
              'message',
              startsWith('exportImage failed:'),
            ),
          ),
        );
      },
    );

    test('the scrubber itself throws a DocumentExportException: it is '
        'rethrown UNCHANGED (message preserved), not re-wrapped as '
        '"exportImage failed: ..."', () async {
      final doc = await repo().createFromCapture(capture);
      await expectLater(
        repo(
          scrubber: const _ThrowingDocumentExportScrubber(),
        ).exportPageAsImage(doc.id, 1),
        throwsA(
          isA<DocumentExportException>().having(
            (e) => e.message,
            'message',
            'scrub boom',
          ),
        ),
      );
    });
  });

  group('exportRecognizedText — write failure wrapping', () {
    test(
      'text export succeeds normally (drives the try path around the '
      'catch at line 544); returns a real .txt file with the OCR content',
      () async {
        final id = await seedEmptyDocument('withtext');
        await db
            .into(db.pages)
            .insert(
              PagesCompanion.insert(
                documentId: id,
                position: 1,
                relativeImagePath: 'documents/$id/page_1.jpg',
                ocrText: const Value('Hello recognized text'),
              ),
            );
        final file = await repo().exportRecognizedText(id, 1);
        expect(file.existsSync(), isTrue);
        expect(file.readAsStringSync(), 'Hello recognized text');
      },
    );
  });

  group('_deleteFlatIfPresent — FileSystemException swallow', () {
    test('updatePageCorners to fullFrame when the flat file was already '
        'deleted out-of-band: still succeeds and clears the DB flat path '
        '(no throw from the missing-file delete)', () async {
      final fakeFlat = Uint8List.fromList([0xFF, 0xD8, 0x99]);
      const corners = CropCorners(
        topLeft: Offset(0.1, 0.1),
        topRight: Offset(0.9, 0.1),
        bottomRight: Offset(0.9, 0.9),
        bottomLeft: Offset(0.1, 0.9),
      );
      final doc = await DriftDocumentRepository(
        db: db,
        scrubber: const JpegExifScrubber(),
        fileStore: DocumentFileStore(base),
        clock: clock,
        pdfBuilder: const PdfBuilder(),
        warper: FakeImageWarper(returnValue: fakeFlat),
      ).createFromCapture(capture, corners: corners);

      final flatFile = File('${base.path}/documents/${doc.id}/page_1_flat.jpg');
      expect(flatFile.existsSync(), isTrue);
      // Delete the flat file out-of-band, so the repo's own delete attempt
      // during the fullFrame reset hits a FileSystemException internally.
      flatFile.deleteSync();

      await expectLater(
        repo().updatePageCorners(doc.id, 1, CropCorners.fullFrame),
        completes,
      );
      final pages = await repo().getDocumentPages(doc.id);
      expect(pages.single.flatImagePath, isNull);
      expect(pages.single.corners, CropCorners.fullFrame);
    });
  });

  group('addPageToDocument — DocumentSaveException passthrough', () {
    test(
      'documentId has no existing pages: rethrows the original '
      '"has no pages" DocumentSaveException untouched (not re-wrapped)',
      () async {
        final id = await seedEmptyDocument('nopages');
        await expectLater(
          repo().addPageToDocument(id, capture),
          throwsA(
            isA<DocumentSaveException>().having(
              (e) => e.message,
              'message',
              'document $id has no pages',
            ),
          ),
        );
      },
    );

    test('a non-DocumentSaveException failure (scrubber throws) IS re-wrapped '
        'as "addPage failed: ..." (not rethrown verbatim)', () async {
      final doc = await repo().createFromCapture(capture);
      final src2 = File('${base.path}/cap2.jpg')
        ..writeAsBytesSync(
          File('test/fixtures/exif_sample.jpg').readAsBytesSync(),
        );
      await expectLater(
        repo(
          scrubber: const _ThrowingScrubber(),
        ).addPageToDocument(doc.id, CapturedImage(src2.path)),
        throwsA(
          isA<DocumentSaveException>().having(
            (e) => e.message,
            'message',
            startsWith('addPage failed:'),
          ),
        ),
      );
    });
  });

  group('deletePage — FileSystemException swallow on file cleanup', () {
    test('deleting one of two pages whose image+flat files were already '
        'removed out-of-band: still succeeds, renumbers survivors, and '
        'returns the correct remaining count', () async {
      final fakeFlat = Uint8List.fromList([0xFF, 0xD8, 0x77]);
      const corners = CropCorners(
        topLeft: Offset(0.1, 0.1),
        topRight: Offset(0.9, 0.1),
        bottomRight: Offset(0.9, 0.9),
        bottomLeft: Offset(0.1, 0.9),
      );
      final r = DriftDocumentRepository(
        db: db,
        scrubber: const JpegExifScrubber(),
        fileStore: DocumentFileStore(base),
        clock: clock,
        pdfBuilder: const PdfBuilder(),
        warper: FakeImageWarper(returnValue: fakeFlat),
      );
      final doc = await r.createFromCapture(capture, corners: corners);
      final src2 = File('${base.path}/cap2.jpg')
        ..writeAsBytesSync(
          File('test/fixtures/exif_sample.jpg').readAsBytesSync(),
        );
      await r.addPageToDocument(
        doc.id,
        CapturedImage(src2.path),
        corners: corners,
      );

      // Remove page 1's base + flat files out-of-band before deleting it.
      File('${base.path}/documents/${doc.id}/page_1.jpg').deleteSync();
      File('${base.path}/documents/${doc.id}/page_1_flat.jpg').deleteSync();

      final remaining = await r.deletePage(doc.id, 1);

      expect(remaining, 1, reason: 'one page (former position 2) remains');
      final pages = await r.getDocumentPages(doc.id);
      expect(pages.single.position, 1, reason: 'renumbered to be contiguous');
    });
  });

  group('replacePage — DocumentSaveException passthrough', () {
    test(
      'replacing a page at a position that does not exist: rethrows the '
      'original "no page" DocumentSaveException untouched (not re-wrapped)',
      () async {
        final doc = await repo().createFromCapture(capture);
        await expectLater(
          repo().replacePage(doc.id, 99, capture),
          throwsA(
            isA<DocumentSaveException>().having(
              (e) => e.message,
              'message',
              'replacePage: no page (${doc.id}, 99)',
            ),
          ),
        );
      },
    );

    test('a non-DocumentSaveException failure (scrubber throws) IS re-wrapped '
        'as "replacePage failed: ..." (not rethrown verbatim)', () async {
      final doc = await repo().createFromCapture(capture);
      final src2 = File('${base.path}/cap2.jpg')
        ..writeAsBytesSync(
          File('test/fixtures/exif_sample.jpg').readAsBytesSync(),
        );
      await expectLater(
        repo(
          scrubber: const _ThrowingScrubber(),
        ).replacePage(doc.id, 1, CapturedImage(src2.path)),
        throwsA(
          isA<DocumentSaveException>().having(
            (e) => e.message,
            'message',
            startsWith('replacePage failed:'),
          ),
        ),
      );
    });
  });

  group('mergeInto — DocumentSaveException passthrough', () {
    test('target == source: rethrows the original "target == source" '
        'DocumentSaveException untouched (not re-wrapped)', () async {
      final doc = await repo().createFromCapture(capture);
      await expectLater(
        repo().mergeInto(doc.id, doc.id),
        throwsA(
          isA<DocumentSaveException>().having(
            (e) => e.message,
            'message',
            'mergeInto: target == source',
          ),
        ),
      );
    });

    test('a non-DocumentSaveException failure (source page image missing on '
        'disk) IS re-wrapped as "mergeInto failed: ..." (not rethrown '
        'verbatim)', () async {
      final targetId = await seedEmptyDocument('mergetarget');
      final sourceId = await seedEmptyDocument('mergesource');
      await db
          .into(db.pages)
          .insert(
            PagesCompanion.insert(
              documentId: sourceId,
              position: 1,
              // never written to disk -> readAsBytes throws PathNotFoundException
              relativeImagePath: 'documents/$sourceId/page_1.jpg',
            ),
          );
      await expectLater(
        repo().mergeInto(targetId, sourceId),
        throwsA(
          isA<DocumentSaveException>().having(
            (e) => e.message,
            'message',
            startsWith('mergeInto failed:'),
          ),
        ),
      );
    });
  });

  group('splitAfter', () {
    test('no pages for documentId: throws DocumentSaveException with the '
        '"no pages" message (line 1079)', () async {
      final id = await seedEmptyDocument('emptysplit');
      await expectLater(
        repo().splitAfter(id, 1),
        throwsA(
          isA<DocumentSaveException>().having(
            (e) => e.message,
            'message',
            'splitAfter: no pages ($id)',
          ),
        ),
      );
    });

    test('position is the last page: throws DocumentSaveException instead of '
        'creating an empty split document', () async {
      final doc = await repo().createFromCapture(capture); // only page 1
      await expectLater(
        repo().splitAfter(doc.id, 1),
        throwsA(
          isA<DocumentSaveException>().having(
            (e) => e.message,
            'message',
            'splitAfter: nothing after position 1',
          ),
        ),
      );
    });

    test('splitting two moved pages that share the SAME physical base file '
        '(cleanup deletes it twice): the first delete succeeds, the second '
        'throws FileSystemException and is swallowed (line 1151); a moved '
        "page's OWN flatRelativePath also coincides with its base path, so "
        'the flat delete right after is swallowed too (line 1158) -- '
        'splitAfter still succeeds and returns a real new document', () async {
      // Seed directly at the DB level: 3 pages under one document. Pages 2
      // and 3 (both "moved" by splitAfter(docId, 1)) point at the SAME
      // on-disk relativeImagePath, and page 2's flatRelativePath also
      // coincides with that same path. Cleanup deletes, in order: page 2's
      // relativeImagePath (succeeds), page 2's flatRelativePath == same
      // file (already gone -> FileSystemException, line 1158), page 3's
      // relativeImagePath == same file (already gone -> FileSystemException,
      // line 1151).
      final docId = await seedEmptyDocument('splitcoincide');
      const page1Rel = 'documents/splitcoincide/page_1.jpg';
      const sharedRel = 'documents/splitcoincide/shared.jpg';
      final fixture = File('test/fixtures/exif_sample.jpg').readAsBytesSync();
      final f1 = File('${base.path}/$page1Rel');
      await f1.create(recursive: true);
      f1.writeAsBytesSync(fixture);
      File('${base.path}/$sharedRel').writeAsBytesSync(fixture);
      await db
          .into(db.pages)
          .insert(
            PagesCompanion.insert(
              documentId: docId,
              position: 1,
              relativeImagePath: page1Rel,
            ),
          );
      await db
          .into(db.pages)
          .insert(
            PagesCompanion.insert(
              documentId: docId,
              position: 2,
              relativeImagePath: sharedRel,
              flatRelativePath: const Value(sharedRel),
            ),
          );
      await db
          .into(db.pages)
          .insert(
            PagesCompanion.insert(
              documentId: docId,
              position: 3,
              relativeImagePath: sharedRel,
            ),
          );

      final newDoc = await repo().splitAfter(docId, 1);

      expect(newDoc.name, endsWith('(split)'));
      final remainingPages = await repo().getDocumentPages(docId);
      expect(remainingPages, hasLength(1), reason: 'pages 2,3 were moved out');
      final newPages = await repo().getDocumentPages(newDoc.id);
      expect(newPages, hasLength(2), reason: 'both moved pages landed here');
      expect(
        File('${base.path}/$sharedRel').existsSync(),
        isFalse,
        reason: 'the shared original file was deleted during cleanup',
      );
    });

    test('splitAfter throws DocumentSaveException for position < 1 (guarded '
        'the same way as "nothing after")', () async {
      final r = repo();
      final doc = await r.createFromCapture(capture);
      final src2 = File('${base.path}/cap2.jpg')
        ..writeAsBytesSync(
          File('test/fixtures/exif_sample.jpg').readAsBytesSync(),
        );
      await r.addPageToDocument(doc.id, CapturedImage(src2.path));
      await expectLater(
        r.splitAfter(doc.id, 0),
        throwsA(isA<DocumentSaveException>()),
      );
    });

    test('a non-DocumentSaveException failure (moved page image missing on '
        'disk) IS re-wrapped as "splitAfter failed: ..." (not rethrown '
        'verbatim)', () async {
      final docId = await seedEmptyDocument('splitmissing');
      const page1Rel = 'documents/splitmissing/page_1.jpg';
      const page2Rel = 'documents/splitmissing/page_2.jpg';
      final f1 = File('${base.path}/$page1Rel');
      await f1.create(recursive: true);
      f1.writeAsBytesSync(
        File('test/fixtures/exif_sample.jpg').readAsBytesSync(),
      );
      await db
          .into(db.pages)
          .insert(
            PagesCompanion.insert(
              documentId: docId,
              position: 1,
              relativeImagePath: page1Rel,
            ),
          );
      await db
          .into(db.pages)
          .insert(
            PagesCompanion.insert(
              documentId: docId,
              position: 2,
              // never written to disk -> readAsBytes throws when copying
              relativeImagePath: page2Rel,
            ),
          );

      await expectLater(
        repo().splitAfter(docId, 1),
        throwsA(
          isA<DocumentSaveException>().having(
            (e) => e.message,
            'message',
            startsWith('splitAfter failed:'),
          ),
        ),
      );
    });
  });

  group('_triggerOcr — fire-and-forget swallow', () {
    test('createFromCapture with an OCR engine that throws: the save still '
        'completes successfully and the page has no OCR text (the OCR '
        'failure never surfaces to the caller)', () async {
      final r = repo(ocrEngine: const _ThrowingOcrEngine());
      final doc = await r.createFromCapture(capture);
      // Let the fire-and-forget OCR future run (and its catchError fire).
      await pumpEventQueue();

      final pages = await r.getDocumentPages(doc.id);
      expect(pages.single.ocrText, isNull);
      // The document row is intact — a throwing OCR engine did not corrupt
      // or abort the save.
      final row = await (db.select(
        db.documents,
      )..where((d) => d.id.equals(doc.id))).getSingle();
      expect(row.id, doc.id);
    });

    test('addPageToDocument with an OCR engine that throws: the new page is '
        'still added successfully with no OCR text cached', () async {
      final r = repo(ocrEngine: const _ThrowingOcrEngine());
      final doc = await r.createFromCapture(capture);
      // A fresh source file: createFromCapture already deleted capture's
      // backing temp file (_deleteTempSource), so it cannot be reused.
      final src2 = File('${base.path}/cap2.jpg')
        ..writeAsBytesSync(
          File('test/fixtures/exif_sample.jpg').readAsBytesSync(),
        );
      final position = await r.addPageToDocument(
        doc.id,
        CapturedImage(src2.path),
      );
      await pumpEventQueue();

      expect(position, 2);
      final pages = await r.getDocumentPages(doc.id);
      expect(pages, hasLength(2));
      expect(pages.last.ocrText, isNull);
    });
  });
}
