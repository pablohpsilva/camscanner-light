import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document_file_store.dart';
import 'package:mobile/features/library/drift/app_database.dart';
import 'package:mobile/features/library/drift/drift_document_repository.dart';
import 'package:mobile/features/library/jpeg_exif_scrubber.dart';
import 'package:mobile/features/library/pdf/pdf_builder.dart';
import 'package:mobile/features/scan/captured_image.dart';

import '../../support/fake_library.dart';

void main() {
  late Directory base;
  late AppDatabase db;
  DateTime clock() => DateTime.utc(2026, 7, 1, 10, 0, 0);

  setUp(() {
    base = Directory.systemTemp.createTempSync('export_id_card');
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

  /// Returns a CapturedImage backed by a copy of the existing test fixture.
  CapturedImage capture(String filename) {
    final src = File('${base.path}/$filename')
      ..writeAsBytesSync(
          File('test/fixtures/exif_sample.jpg').readAsBytesSync());
    return CapturedImage(src.path);
  }

  test('exportPdf of an ID-card document yields a single-page PDF', () async {
    final r = repo();
    final doc = await r.createFromCapture(capture('front.jpg'));
    await r.addPageToDocument(doc.id, capture('back.jpg'));
    await r.markAsIdCard(doc.id);

    final file = await r.exportPdf(doc.id);

    final bytes = await file.readAsBytes();
    final s = String.fromCharCodes(bytes);
    final pageMatches = RegExp(r'/Type\s*/Page(?![s])').allMatches(s);
    expect(pageMatches.length, 1,
        reason: 'ID-card export must produce exactly one PDF page');
  });

  test('exportPdf of a non-ID-card 2-page document yields two PDF pages',
      () async {
    final r = repo();
    final doc = await r.createFromCapture(capture('p1.jpg'));
    await r.addPageToDocument(doc.id, capture('p2.jpg'));
    // Do NOT markAsIdCard — ordinary doc.

    final file = await r.exportPdf(doc.id);

    final bytes = await file.readAsBytes();
    final s = String.fromCharCodes(bytes);
    final pageMatches = RegExp(r'/Type\s*/Page(?![s])').allMatches(s);
    expect(pageMatches.length, 2,
        reason: 'Non-ID-card export must produce one page per document page');
  });
}
