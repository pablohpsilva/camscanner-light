import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document_repository.dart';
import 'package:mobile/features/library/drift/app_database.dart';
import 'package:mobile/features/library/drift/drift_document_repository.dart';
import 'package:mobile/features/library/document_file_store.dart';
import 'package:mobile/features/library/jpeg_exif_scrubber.dart';
import 'package:mobile/features/library/pdf/pdf_builder.dart';
import 'package:mobile/features/scan/captured_image.dart';

import '../../support/fake_library.dart';

void main() {
  late Directory base;
  late AppDatabase db;
  DateTime clock() => DateTime.utc(2026, 7, 1, 10, 0, 0);

  setUp(() {
    base = Directory.systemTemp.createTempSync('mark_id_card');
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
        File('test/fixtures/exif_sample.jpg').readAsBytesSync(),
      );
    return CapturedImage(src.path);
  }

  group('DriftDocumentRepository.markAsIdCard', () {
    test('sets isIdCard to true and bumps modifiedAt', () async {
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

      final doc = await r.createFromCapture(capture('cap.jpg'));
      final before = await (db.select(
        db.documents,
      )..where((d) => d.id.equals(doc.id))).getSingle();

      await r.markAsIdCard(doc.id);

      final after = await (db.select(
        db.documents,
      )..where((d) => d.id.equals(doc.id))).getSingle();

      expect(
        after.isIdCard,
        isTrue,
        reason: 'isIdCard must be set to true after markAsIdCard',
      );
      expect(
        after.modifiedAt.isAfter(before.modifiedAt) ||
            after.modifiedAt == before.modifiedAt,
        isTrue,
        reason: 'modifiedAt must not regress',
      );
    });

    test('modifiedAt is bumped to the clock time at call site', () async {
      final createdAt = DateTime.utc(2026, 7, 1, 10, 0, 0);
      final markedAt = DateTime.utc(2026, 7, 1, 10, 5, 0);
      int tick = 0;
      final r = DriftDocumentRepository(
        db: db,
        scrubber: const JpegExifScrubber(),
        fileStore: DocumentFileStore(base),
        clock: () => tick++ < 1 ? createdAt : markedAt,
        pdfBuilder: const PdfBuilder(),
        warper: FakeImageWarper(),
      );

      final doc = await r.createFromCapture(capture('cap2.jpg'));
      await r.markAsIdCard(doc.id);

      final row = await (db.select(
        db.documents,
      )..where((d) => d.id.equals(doc.id))).getSingle();

      expect(
        row.modifiedAt,
        markedAt,
        reason: 'modifiedAt must equal the clock value at markAsIdCard call',
      );
    });

    test('throws DocumentSaveException for a missing document', () async {
      final r = repo();
      await expectLater(
        r.markAsIdCard(999),
        throwsA(isA<DocumentSaveException>()),
      );
    });
  });

  group('FakeDocumentRepository.markAsIdCard', () {
    test('records the id in markIdCardCalls', () async {
      final fake = FakeDocumentRepository();
      await fake.markAsIdCard(42);
      await fake.markAsIdCard(7);
      expect(fake.markIdCardCalls, [42, 7]);
    });
  });
}
