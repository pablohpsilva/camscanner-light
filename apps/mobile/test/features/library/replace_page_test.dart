import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/library/document_file_store.dart';
import 'package:mobile/features/library/document_repository.dart';
import 'package:mobile/features/library/drift/app_database.dart';
import 'package:mobile/features/library/drift/drift_document_repository.dart';
import 'package:mobile/features/library/jpeg_exif_scrubber.dart';
import 'package:mobile/features/library/pdf/pdf_builder.dart';
import 'package:mobile/features/scan/captured_image.dart';

import '../../support/fake_library.dart'; // provides FakeDocumentRepository + FakeImageWarper

void main() {
  late Directory base;
  late AppDatabase db;
  // ignore: prefer_function_declarations_over_variables
  final clock = () => DateTime.utc(2026, 6, 27, 20, 26, 42);

  setUp(() {
    base = Directory.systemTemp.createTempSync('h4rep');
    db = AppDatabase(NativeDatabase.memory());
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

  CapturedImage freshCapture(String filename) {
    final src = File('${base.path}/$filename')
      ..writeAsBytesSync(
          File('test/fixtures/exif_sample.jpg').readAsBytesSync());
    return CapturedImage(src.path);
  }

  const corners = CropCorners(
    topLeft: Offset(0.1, 0.1), topRight: Offset(0.9, 0.1),
    bottomRight: Offset(0.9, 0.9), bottomLeft: Offset(0.1, 0.9));

  test('replacePage (full-frame) overwrites the image and clears corners',
      () async {
    final r = repo();
    final doc = await r.createFromCapture(freshCapture('c1.jpg'),
        corners: corners); // page 1 starts with a flat + corners
    final rel = 'documents/${doc.id}/page_1.jpg';
    final absPath = '${base.path}/$rel';

    await r.replacePage(doc.id, 1, freshCapture('c1b.jpg')); // full-frame

    expect(File(absPath).existsSync(), isTrue,
        reason: 'image overwritten in place at the same path');
    final page = (await db.select(db.pages).get()).single;
    expect(page.position, 1);
    expect(page.corners, isNull, reason: 'corners cleared for full-frame');
    expect(page.flatRelativePath, isNull,
        reason: 'flat derivative dropped for full-frame');
  });

  test('replacePage with corners writes a flat and stores corners', () async {
    final r = repo();
    final doc = await r.createFromCapture(freshCapture('c1.jpg')); // full-frame

    await r.replacePage(doc.id, 1, freshCapture('c1b.jpg'), corners: corners);

    final page = (await db.select(db.pages).get()).single;
    expect(page.corners, isNotNull, reason: 'corners stored');
    expect(page.flatRelativePath, isNotNull, reason: 'flat written');
    expect(File('${base.path}/${page.flatRelativePath}').existsSync(), isTrue);
  });

  test('replacePage on a non-existent position throws DocumentSaveException',
      () async {
    final r = repo();
    final doc = await r.createFromCapture(freshCapture('c1.jpg'));
    await expectLater(
      r.replacePage(doc.id, 99, freshCapture('c2.jpg')),
      throwsA(isA<DocumentSaveException>()),
    );
  });

  test('replacePage reuses the existing flat path (no orphaned derivative)',
      () async {
    const cornersB = CropCorners(
      topLeft: Offset(0.2, 0.2), topRight: Offset(0.8, 0.2),
      bottomRight: Offset(0.8, 0.8), bottomLeft: Offset(0.2, 0.8));

    final r = repo();
    // Page 1 starts non-full-frame: a flat derivative is written.
    final doc = await r.createFromCapture(freshCapture('c1.jpg'),
        corners: corners);

    final beforePath = (await db.select(db.pages).get()).single.flatRelativePath;
    expect(beforePath, isNotNull, reason: 'flat must exist before replace');

    // Replace with DIFFERENT non-full-frame corners — flat must be overwritten
    // at the SAME relative path, not written to a new derivative path.
    await r.replacePage(doc.id, 1, freshCapture('c1c.jpg'), corners: cornersB);

    final afterPath = (await db.select(db.pages).get()).single.flatRelativePath;
    expect(afterPath, equals(beforePath),
        reason: 'flat path must be reused; no orphaned derivative allowed');
    expect(File('${base.path}/$afterPath').existsSync(), isTrue,
        reason: 'flat file must exist at the reused path');
  });

  test('replacePage after reorder does not collide with another page\'s flat',
      () async {
    final r = repo();

    // 1. Create doc: page 1 full-frame — image page_1.jpg, no flat.
    final doc = await r.createFromCapture(freshCapture('a.jpg'));

    // 2. Add page 2 with corners — writes flat page_2_flat.jpg.
    await r.addPageToDocument(doc.id, freshCapture('b.jpg'), corners: corners);

    // Capture page 2's stored flatRelativePath before the reorder.
    final pagesAfterAdd = await db.select(db.pages).get();
    final page2RowBefore =
        pagesAfterAdd.firstWhere((p) => p.relativeImagePath.endsWith('page_2.jpg'));
    final page2FlatBefore = page2RowBefore.flatRelativePath;
    expect(page2FlatBefore, isNotNull,
        reason: 'page 2 must have a flat after addPageToDocument with corners');

    // 3. reorderPages: page B (old position 2) → position 1,
    //    page A (old position 1) → position 2.
    await r.reorderPages(doc.id, [2, 1]);

    // 4. Retake page A (now at position 2) WITH corners.
    const retakeCorners = CropCorners(
      topLeft: Offset(0.2, 0.2), topRight: Offset(0.8, 0.2),
      bottomRight: Offset(0.8, 0.8), bottomLeft: Offset(0.2, 0.8));
    await r.replacePage(doc.id, 2, freshCapture('a2.jpg'),
        corners: retakeCorners);

    // 5. Query both page rows.
    final allPages = await db.select(db.pages).get();
    final pageA =
        allPages.firstWhere((p) => p.relativeImagePath.endsWith('page_1.jpg'));
    final pageB =
        allPages.firstWhere((p) => p.relativeImagePath.endsWith('page_2.jpg'));

    // page A's flat must be derived from ITS OWN image path (page_1_flat.jpg).
    expect(pageA.flatRelativePath, isNotNull);
    expect(pageA.flatRelativePath!.endsWith('page_1_flat.jpg'), isTrue,
        reason: 'page A flat must be derived from its image path, not position');

    // page B's flat must be UNCHANGED (page_2_flat.jpg, not overwritten).
    expect(pageB.flatRelativePath, equals(page2FlatBefore),
        reason: 'page B flat must not be overwritten by page A\'s retake');
    expect(pageB.flatRelativePath!.endsWith('page_2_flat.jpg'), isTrue);

    // Collision guard: the two flat paths must be different.
    expect(pageA.flatRelativePath, isNot(equals(pageB.flatRelativePath)),
        reason: 'flat paths must differ — collision means silent corruption');

    // Both flat files must exist on disk.
    expect(File('${base.path}/${pageA.flatRelativePath}').existsSync(), isTrue,
        reason: 'page A flat file must exist on disk');
    expect(File('${base.path}/${pageB.flatRelativePath}').existsSync(), isTrue,
        reason: 'page B flat file must exist on disk');
  });
}
