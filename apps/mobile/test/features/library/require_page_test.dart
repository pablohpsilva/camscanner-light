import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document_file_store.dart';
import 'package:mobile/features/library/document_repository.dart';
import 'package:mobile/features/library/drift/app_database.dart';
import 'package:mobile/features/library/drift/drift_document_repository.dart';
import 'package:mobile/features/library/jpeg_exif_scrubber.dart';
import 'package:mobile/features/library/pdf/pdf_builder.dart';

import '../../support/fake_library.dart';

/// P10 T10.1: a missing (documentId, position) page must throw the SAME
/// exception type + message after the `_requirePage` extraction as before —
/// save methods throw [DocumentSaveException], the two export methods throw
/// [DocumentExportException]. This pins the type-parameterization.
void main() {
  late Directory base;
  late AppDatabase db;

  setUp(() {
    base = Directory.systemTemp.createTempSync('reqpage');
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
    clock: () => DateTime.utc(2026, 1, 1),
    pdfBuilder: const PdfBuilder(),
    warper: FakeImageWarper(),
  );

  Future<int> seedEmptyDoc() => db
      .into(db.documents)
      .insert(
        DocumentsCompanion.insert(
          name: 'd',
          createdAt: DateTime.utc(2026, 1, 1),
          modifiedAt: DateTime.utc(2026, 1, 1),
        ),
      );

  test('rotatePage on a missing page → DocumentSaveException', () async {
    final id = await seedEmptyDoc();
    await expectLater(
      repo().rotatePage(id, 1),
      throwsA(
        isA<DocumentSaveException>().having(
          (e) => e.message,
          'message',
          'rotatePage: no page ($id, 1)',
        ),
      ),
    );
  });

  test('deletePage on a missing page → DocumentSaveException', () async {
    final id = await seedEmptyDoc();
    await expectLater(
      repo().deletePage(id, 1),
      throwsA(
        isA<DocumentSaveException>().having(
          (e) => e.message,
          'message',
          'deletePage: no page ($id, 1)',
        ),
      ),
    );
  });

  test(
    'exportPageAsImage on a missing page → DocumentExportException',
    () async {
      final id = await seedEmptyDoc();
      await expectLater(
        repo().exportPageAsImage(id, 1),
        throwsA(
          isA<DocumentExportException>().having(
            (e) => e.message,
            'message',
            'exportImage failed: no page ($id, 1)',
          ),
        ),
      );
    },
  );

  test(
    'exportRecognizedText on a missing page → DocumentExportException',
    () async {
      final id = await seedEmptyDoc();
      await expectLater(
        repo().exportRecognizedText(id, 1),
        throwsA(
          isA<DocumentExportException>().having(
            (e) => e.message,
            'message',
            'exportText failed: no page ($id, 1)',
          ),
        ),
      );
    },
  );
}
