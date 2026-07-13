import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document.dart';
import 'package:mobile/features/library/document_file_store.dart';
import 'package:mobile/features/library/drift/app_database.dart' hide Document;
import 'package:mobile/features/library/drift/drift_document_repository.dart';
import 'package:mobile/features/library/jpeg_exif_scrubber.dart';
import 'package:mobile/features/library/pdf/pdf_builder.dart';
import 'package:mobile/features/scan/captured_image.dart';

import '../../../support/fake_library.dart';

void main() {
  late Directory base;
  late AppDatabase db;
  late CapturedImage capture;
  // ignore: prefer_function_declarations_over_variables
  final clock = () => DateTime.utc(2026, 6, 27, 20, 26, 42);

  setUp(() {
    base = Directory.systemTemp.createTempSync('tagrepo');
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

  Future<Document> _seedOneDoc(DriftDocumentRepository r) =>
      r.createFromCapture(capture);

  // Writes ocr_text directly on the page row at [documentId]/[position],
  // mirroring how existing tests reach into the in-memory DB (repo() itself
  // never exposes ocrText writes outside of OCR-engine flow).
  Future<void> setPageOcrText(
    int documentId,
    int position,
    String text,
  ) async {
    final page = await (db.select(db.pages)..where(
          (t) =>
              t.documentId.equals(documentId) & t.position.equals(position),
        ))
        .getSingle();
    await (db.update(db.pages)..where((t) => t.id.equals(page.id))).write(
      PagesCompanion(ocrText: Value(text)),
    );
  }

  test('createTag dedupes case-insensitively', () async {
    final r = repo();
    final a = await r.createTag('Tax');
    final b = await r.createTag('tax');
    expect(b.id, a.id);
    expect((await r.listTags()).length, 1);
  });

  test('setDocumentTags replaces the set; tagsForDocument reflects it', () async {
    final r = repo();
    final doc = await _seedOneDoc(r);
    final t1 = await r.createTag('a');
    final t2 = await r.createTag('b');
    await r.setDocumentTags(doc.id, {t1.id, t2.id});
    expect((await r.tagsForDocument(doc.id)).map((t) => t.name), ['a', 'b']);
    await r.setDocumentTags(doc.id, {t2.id});
    expect((await r.tagsForDocument(doc.id)).map((t) => t.name), ['b']);
  });

  test('summary is enriched with tags', () async {
    final r = repo();
    final doc = await _seedOneDoc(r);
    final t = await r.createTag('tax');
    await r.setDocumentTags(doc.id, {t.id});
    expect((await r.listDocumentSummaries()).single.tags.single.name, 'tax');
  });

  test('deleting a document cascade-removes its tag links (no leak)', () async {
    final r = repo();
    final doc = await _seedOneDoc(r);
    final t = await r.createTag('tax');
    await r.setDocumentTags(doc.id, {t.id});
    await r.deleteDocument(doc.id);
    expect(await r.tagsForDocument(doc.id), isEmpty);
    expect((await r.listTags()).length, 1); // the tag itself survives
  });

  test('suggestTitleFor returns null before OCR, value after', () async {
    final r = repo(); // repo() uses NoOpOcrEngine by default
    final doc = await _seedOneDoc(r);
    expect(await r.suggestTitleFor(doc.id), isNull);
    // simulate OCR having run by writing ocr_text directly through the DB.
    await setPageOcrText(doc.id, 1, 'INVOICE\nAcme');
    expect(await r.suggestTitleFor(doc.id), 'INVOICE');
  });
}
