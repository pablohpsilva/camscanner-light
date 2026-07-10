import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/library/document_file_store.dart';
import 'package:mobile/features/library/document_repository.dart';
import 'package:mobile/features/library/drift/app_database.dart';
import 'package:mobile/features/library/drift/drift_document_repository.dart';
import 'package:mobile/features/library/grayscale_enhancer.dart';
import 'package:mobile/features/library/jpeg_exif_scrubber.dart';
import 'package:mobile/features/library/pdf/pdf_builder.dart';
import 'package:mobile/features/library/save_controller.dart';
import 'package:mobile/features/scan/captured_image.dart';

import '../../support/fake_library.dart';

void main() {
  late Directory base;
  late AppDatabase db;
  late CapturedImage capture;
  DateTime clock() => DateTime.utc(2026, 7, 1, 10, 0, 0);

  setUp(() {
    base = Directory.systemTemp.createTempSync('h1repo');
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

  DriftDocumentRepository repo() => DriftDocumentRepository(
    db: db,
    scrubber: const JpegExifScrubber(),
    fileStore: DocumentFileStore(base),
    clock: clock,
    pdfBuilder: const PdfBuilder(),
    warper: FakeImageWarper(),
  );

  // Helper: returns a fresh CapturedImage backed by a copy of exif_sample.jpg.
  CapturedImage freshCapture(String filename) {
    final src = File('${base.path}/$filename')
      ..writeAsBytesSync(
        File('test/fixtures/exif_sample.jpg').readAsBytesSync(),
      );
    return CapturedImage(src.path);
  }

  group('DriftDocumentRepository.addPageToDocument', () {
    test(
      'appends page at position MAX+1 (position 2 after createFromCapture)',
      () async {
        final r = repo();
        final doc = await r.createFromCapture(capture);

        final position = await r.addPageToDocument(
          doc.id,
          freshCapture('cap2.jpg'),
        );

        expect(position, 2);
        expect(
          File('${base.path}/documents/${doc.id}/page_2.jpg').existsSync(),
          isTrue,
          reason: 'page_2.jpg must be written on disk',
        );
        final pages = await db.select(db.pages).get();
        expect(pages.length, 2);
        expect(pages.last.position, 2);
      },
    );

    test('throws DocumentSaveException for document with no pages', () async {
      final r = repo();
      // Insert a document row with no pages (inconsistent state).
      final docId = await db
          .into(db.documents)
          .insert(
            DocumentsCompanion.insert(
              name: 'empty',
              createdAt: clock().toUtc(),
              modifiedAt: clock().toUtc(),
            ),
          );

      await expectLater(
        r.addPageToDocument(docId, capture),
        throwsA(isA<DocumentSaveException>()),
      );
    });

    test('bumps modifiedAt on parent document', () async {
      int tick = 0;
      final times = [
        DateTime.utc(2026, 7, 1, 10, 0, 0),
        DateTime.utc(2026, 7, 1, 10, 1, 0),
      ];
      final r = DriftDocumentRepository(
        db: db,
        scrubber: const JpegExifScrubber(),
        fileStore: DocumentFileStore(base),
        clock: () => times[tick++ < 1 ? 0 : 1],
        pdfBuilder: const PdfBuilder(),
        warper: FakeImageWarper(),
      );

      final doc = await r.createFromCapture(capture);
      await r.addPageToDocument(doc.id, freshCapture('cap2.jpg'));

      final row = await (db.select(
        db.documents,
      )..where((d) => d.id.equals(doc.id))).getSingle();
      expect(
        row.modifiedAt,
        DateTime.utc(2026, 7, 1, 10, 1, 0),
        reason: 'modifiedAt must be updated to addPage clock time',
      );
    });

    test('full-frame path: applies enhancer without error', () async {
      final r = repo();
      final doc = await r.createFromCapture(capture);

      final position = await r.addPageToDocument(
        doc.id,
        freshCapture('cap2.jpg'),
        enhancer: const GrayscaleEnhancer(),
      );
      expect(position, 2);
    });

    test(
      'crop path: warped flat file written when warper returns bytes',
      () async {
        final fakeWarper = FakeImageWarper(
          returnValue: File('test/fixtures/exif_sample.jpg').readAsBytesSync(),
        );
        final r = DriftDocumentRepository(
          db: db,
          scrubber: const JpegExifScrubber(),
          fileStore: DocumentFileStore(base),
          clock: clock,
          pdfBuilder: const PdfBuilder(),
          warper: fakeWarper,
        );

        final doc = await r.createFromCapture(capture);
        final corners = CropCorners(
          topLeft: const Offset(0.1, 0.1),
          topRight: const Offset(0.9, 0.1),
          bottomRight: const Offset(0.9, 0.9),
          bottomLeft: const Offset(0.1, 0.9),
        );
        await r.addPageToDocument(
          doc.id,
          freshCapture('cap2.jpg'),
          corners: corners,
        );

        expect(
          File('${base.path}/documents/${doc.id}/page_2_flat.jpg').existsSync(),
          isTrue,
          reason: 'flat file must be written for crop path',
        );
        expect(fakeWarper.calls, greaterThan(0));
      },
    );
  });

  group('SaveController.addPage', () {
    test('returns position on success and transitions to idle', () async {
      final fakeRepo = FakeDocumentRepository();
      final c = SaveController(repository: fakeRepo);
      final states = <SaveStatus>[];
      c.addListener(() => states.add(c.status));

      // Create first page.
      final doc = await c.save(const CapturedImage('/tmp/cap.jpg'));
      states.clear();

      final pos = await c.addPage(
        const CapturedImage('/tmp/cap2.jpg'),
        doc!.id,
      );

      expect(pos, 2, reason: 'fake returns addPageCalls + 1 = 2');
      expect(fakeRepo.addPageCalls, 1);
      expect(c.status, SaveStatus.idle);
      expect(states, containsAllInOrder([SaveStatus.saving, SaveStatus.idle]));
      c.dispose();
    });

    test(
      'returns null and transitions to error on repository failure',
      () async {
        final fakeRepo = FakeDocumentRepository(throwOnAddPage: true);
        final c = SaveController(repository: fakeRepo);

        final pos = await c.addPage(const CapturedImage('/tmp/cap.jpg'), 42);

        expect(pos, isNull);
        expect(c.status, SaveStatus.error);
        c.dispose();
      },
    );

    test('second addPage while one in-flight is ignored', () async {
      final gate = Completer<void>();
      // gate blocks addPageToDocument in fake
      final fakeRepo = FakeDocumentRepository(addPageGate: gate);
      final c = SaveController(repository: fakeRepo);
      // Create doc first so addPage can proceed.
      await c.save(const CapturedImage('/tmp/cap.jpg'));

      final first = c.addPage(const CapturedImage('/tmp/cap2.jpg'), 1);
      final second = await c.addPage(const CapturedImage('/tmp/cap3.jpg'), 1);
      expect(second, isNull, reason: 'in-flight → ignored');
      expect(fakeRepo.addPageCalls, 1);

      gate.complete();
      expect(await first, isNotNull);
      c.dispose();
    });
  });
}
