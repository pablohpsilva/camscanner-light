import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
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
    base = Directory.systemTemp.createTempSync('h4del');
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

  test('deleting a middle page renumbers survivors and removes its files',
      () async {
    final r = repo();
    final doc = await r.createFromCapture(freshCapture('c1.jpg')); // pos 1
    await r.addPageToDocument(doc.id, freshCapture('c2.jpg')); // pos 2
    await r.addPageToDocument(doc.id, freshCapture('c3.jpg')); // pos 3

    final before = await r.getDocumentPages(doc.id);
    final page2Path = before[1].imagePath; // absolute path of page at pos 2
    expect(File(page2Path).existsSync(), isTrue);

    final remaining = await r.deletePage(doc.id, 2);

    expect(remaining, 2);
    final after = await r.getDocumentPages(doc.id);
    expect(after.map((p) => p.position), [1, 2],
        reason: 'survivors renumbered contiguously');
    expect(File(page2Path).existsSync(), isFalse,
        reason: "deleted page's image file removed (best-effort)");
  });

  test('deleting the only page deletes the whole document (returns 0)',
      () async {
    final r = repo();
    final doc = await r.createFromCapture(freshCapture('c1.jpg'));

    final remaining = await r.deletePage(doc.id, 1);

    expect(remaining, 0);
    expect(await db.select(db.documents).get(), isEmpty,
        reason: 'last-page rule: document row deleted');
    expect(Directory('${base.path}/documents/${doc.id}').existsSync(), isFalse,
        reason: 'document dir nuked');
  });

  test('deleting a non-existent position throws DocumentSaveException',
      () async {
    final r = repo();
    final doc = await r.createFromCapture(freshCapture('c1.jpg'));
    await expectLater(
      r.deletePage(doc.id, 99),
      throwsA(isA<DocumentSaveException>()),
    );
  });
}
