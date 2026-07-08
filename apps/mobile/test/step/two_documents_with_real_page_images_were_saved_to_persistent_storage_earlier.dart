import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/drift/app_database.dart';

import '../support/persistent_storage.dart';
import 'a_document_with_a_real_page_image_was_saved_to_persistent_storage_earlier.dart';

/// Usage: two documents with real page images were saved to persistent storage earlier
///
/// Seeds two documents, each with one page row and a real page image, into the
/// same on-disk storage. Used by features that operate across two documents
/// (merge, share-as-zip) without the custom camera flow.
Future<void> twoDocumentsWithRealPageImagesWereSavedToPersistentStorageEarlier(
    WidgetTester tester) async {
  final dir = await Directory.systemTemp.createTemp('seedimg2docs');
  persistentDir = dir;
  persistentDbFile = File('${dir.path}/camscanner.sqlite');

  addTearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  final db = AppDatabase(NativeDatabase(persistentDbFile!));
  for (var i = 0; i < 2; i++) {
    final docId = await db.into(db.documents).insert(DocumentsCompanion.insert(
          name: 'Scan 2026-06-27 20.26.4$i',
          createdAt: DateTime.utc(2026, 6, 27, 20, 26, 40 + i),
          modifiedAt: DateTime.utc(2026, 6, 27, 20, 26, 40 + i),
        ));
    await db.into(db.pages).insert(PagesCompanion.insert(
          documentId: docId,
          position: 1,
          relativeImagePath: 'documents/$docId/page_1.jpg',
        ));
    await writeSeededPageImage(dir, docId, 1);
  }
  await db.close();
}
