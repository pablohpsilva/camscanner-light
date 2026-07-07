import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:exif/exif.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:mobile/features/library/document_file_store.dart';
import 'package:mobile/features/library/document_repository.dart';
import 'package:mobile/features/library/drift/app_database.dart';
import 'package:mobile/features/library/drift/drift_document_repository.dart';
import 'package:mobile/features/library/jpeg_exif_scrubber.dart';
import 'package:mobile/features/library/pdf/pdf_builder.dart';

import '../../support/fake_library.dart';

void main() {
  late Directory base;
  late AppDatabase db;
  // ignore: prefer_function_declarations_over_variables
  final clock = () => DateTime.utc(2026, 6, 27, 20, 26, 42);

  setUp(() {
    base = Directory.systemTemp.createTempSync('i1exp');
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

  Uint8List fixture(String name) =>
      File('test/fixtures/$name').readAsBytesSync();

  // Seed a document + one page, writing the image file(s) directly (NOT via
  // the warper — export only reads the stored display file).
  Future<int> seedDoc({required String image, String? flat}) async {
    final now = clock();
    final store = DocumentFileStore(base);
    final docId = await db.into(db.documents).insert(
        DocumentsCompanion.insert(name: 'Doc', createdAt: now, modifiedAt: now));
    final rel = 'documents/$docId/page_1.jpg';
    await store.writeRelative(rel, fixture(image));
    String? flatRel;
    if (flat != null) {
      flatRel = 'documents/$docId/page_1_flat.jpg';
      await store.writeRelative(flatRel, fixture(flat));
    }
    await db.into(db.pages).insert(PagesCompanion.insert(
          documentId: docId,
          position: 1,
          relativeImagePath: rel,
          flatRelativePath: Value(flatRel),
        ));
    return docId;
  }

  test('exports a scrubbed JPG (no EXIF) at the export path', () async {
    final docId = await seedDoc(image: 'exif_sample.jpg');

    final file = await repo().exportPageAsImage(docId, 1);

    // Privacy: the export must NOT land in the persistent document store
    // (that dir is included in Google/iCloud backups and accumulates forever).
    // It belongs in the OS temp/cache dir — self-purging and backup-excluded.
    expect(file.existsSync(), isTrue);
    expect(p.isWithin(base.path, file.path), isFalse,
        reason: 'export must not be written into the persistent, backed-up store');
    expect(p.isWithin(Directory.systemTemp.path, file.path), isTrue,
        reason: 'export belongs in the OS temp/cache dir');
    expect(file.path, endsWith('.jpg'));
    final bytes = file.readAsBytesSync();
    expect(bytes.sublist(0, 2), [0xFF, 0xD8], reason: 'valid JPEG header');
    // The scrubber removes IDENTIFYING/personal EXIF but intentionally KEEPS
    // Orientation (rotation preserved losslessly). So assert the personal tags
    // are gone — mirroring the JpegExifScrubber test — NOT that EXIF is empty.
    final tags = await readExifFromBytes(bytes);
    expect(tags['Image Make'], isNull);
    expect(tags['Image Model'], isNull);
    expect(tags['Image Software'], isNull);
    expect(tags['Image DateTime'], isNull);
    expect(tags.keys.where((k) => k.startsWith('GPS')), isEmpty,
        reason: 'exported image has no GPS/personal metadata');
    // Positively lock the "Orientation kept" contract through the export path:
    // the scrub must PRESERVE Orientation, not strip all EXIF (which would make
    // the personal-tag-absence checks above pass vacuously).
    expect(tags['Image Orientation'].toString(), 'Rotated 90 CW',
        reason: 'export preserves Orientation losslessly');
  });

  test('uses the flat image when flatRelativePath is set', () async {
    final docId =
        await seedDoc(image: 'exif_sample.jpg', flat: 'landscape_exif6.jpg');

    final file = await repo().exportPageAsImage(docId, 1);

    final exported = file.readAsBytesSync();
    final expectedFromFlat =
        const JpegExifScrubber().scrub(fixture('landscape_exif6.jpg'));
    expect(exported, expectedFromFlat,
        reason: 'export uses the scrubbed flat derivative, not the original');
  });

  test('missing page throws DocumentExportException', () async {
    final docId = await seedDoc(image: 'exif_sample.jpg');
    await expectLater(
      repo().exportPageAsImage(docId, 99),
      throwsA(isA<DocumentExportException>()),
    );
  });
}
