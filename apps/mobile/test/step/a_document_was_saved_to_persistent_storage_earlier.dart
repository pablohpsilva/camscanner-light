import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/drift/app_database.dart';

import '../support/persistent_storage.dart';

/// Usage: a document was saved to persistent storage earlier
///
/// Seeds a document + one page DIRECTLY into an on-disk SQLite file via a
/// throwaway connection, then closes it — modelling "this data was persisted
/// before the current app instance started". No image file is written, so the
/// thumbnail will resolve to a placeholder (which also exercises the
/// missing-file path on-device); the home assertion only needs the row.
Future<void> aDocumentWasSavedToPersistentStorageEarlier(
  WidgetTester tester,
) async {
  final dir = await Directory.systemTemp.createTemp('b2persist');
  persistentDir = dir;
  persistentDbFile = File('${dir.path}/camscanner.sqlite');

  addTearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  final db = AppDatabase(NativeDatabase(persistentDbFile!));
  final docId = await db
      .into(db.documents)
      .insert(
        DocumentsCompanion.insert(
          name: 'Scan 2026-06-27 20.26.42',
          createdAt: DateTime.utc(2026, 6, 27, 20, 26, 42),
          modifiedAt: DateTime.utc(2026, 6, 27, 20, 26, 42),
        ),
      );
  await db
      .into(db.pages)
      .insert(
        PagesCompanion.insert(
          documentId: docId,
          position: 1,
          relativeImagePath: 'documents/$docId/page_1.jpg',
        ),
      );
  await db.close();
}
