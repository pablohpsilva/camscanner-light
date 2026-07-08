import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/drift/app_database.dart';

import '../support/persistent_storage.dart';
import 'a_document_with_a_real_page_image_was_saved_to_persistent_storage_earlier.dart';

/// Usage: a document with 3 real page images was saved to persistent storage earlier
///
/// Seeds one document with three page rows (positions 1..3) and writes real JPEG
/// bytes for each, so the multi-page PDF export feature can assert a 3-page PDF
/// against a seeded document without the custom camera flow.
Future<void> aDocumentWith3RealPageImagesWasSavedToPersistentStorageEarlier(
    WidgetTester tester) async {
  final dir = await Directory.systemTemp.createTemp('seedimg3');
  persistentDir = dir;
  persistentDbFile = File('${dir.path}/camscanner.sqlite');

  addTearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  final db = AppDatabase(NativeDatabase(persistentDbFile!));
  final docId = await db.into(db.documents).insert(DocumentsCompanion.insert(
        name: 'Scan 2026-06-27 20.26.42',
        createdAt: DateTime.utc(2026, 6, 27, 20, 26, 42),
        modifiedAt: DateTime.utc(2026, 6, 27, 20, 26, 42),
      ));
  for (final position in [1, 2, 3]) {
    await db.into(db.pages).insert(PagesCompanion.insert(
          documentId: docId,
          position: position,
          relativeImagePath: 'documents/$docId/page_$position.jpg',
        ));
  }
  await db.close();

  for (final position in [1, 2, 3]) {
    await writeSeededPageImage(dir, docId, position);
  }
}
