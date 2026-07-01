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
}
