import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/drift/app_database.dart';

import '../support/fake_scan.dart';
import '../support/persistent_storage.dart';

/// Usage: a document with a real page image was saved to persistent storage earlier
///
/// Like [aDocumentWasSavedToPersistentStorageEarlier], but ALSO writes real JPEG
/// bytes ([kFakeJpegBytes]) to the page's image file (and its `_flat` derivative)
/// under `persistentDir`, mirroring [DocumentFileStore]'s layout
/// (`documents/$docId/page_$position.jpg`). This lets image-reading features
/// (rotate / export / PDF / print / share) run against a seeded document without
/// the custom camera flow.
Future<void> aDocumentWithARealPageImageWasSavedToPersistentStorageEarlier(
    WidgetTester tester) async {
  final dir = await Directory.systemTemp.createTemp('seedimg');
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
  await db.into(db.pages).insert(PagesCompanion.insert(
        documentId: docId,
        position: 1,
        relativeImagePath: 'documents/$docId/page_1.jpg',
      ));
  await db.close();

  await _writePageImage(dir, docId, 1);
}

/// Writes [kFakeJpegBytes] to the page image at [position] and its `_flat`
/// derivative, creating parent directories. Shared by the multi-page and
/// two-document seed steps.
Future<void> writeSeededPageImage(
    Directory baseDir, int docId, int position) async {
  await _writePageImage(baseDir, docId, position);
}

Future<void> _writePageImage(Directory baseDir, int docId, int position) async {
  final docDir = Directory('${baseDir.path}/documents/$docId');
  await docDir.create(recursive: true);
  await File('${docDir.path}/page_$position.jpg').writeAsBytes(kFakeJpegBytes);
  await File('${docDir.path}/page_${position}_flat.jpg')
      .writeAsBytes(kFakeJpegBytes);
}
