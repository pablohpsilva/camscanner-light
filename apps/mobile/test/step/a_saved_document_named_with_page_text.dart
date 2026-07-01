import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/drift/app_database.dart';

import '../support/persistent_storage.dart';

/// Usage: a saved document named {'Untitled'} with page text {'INVOICE 2026'}
Future<void> aSavedDocumentNamedWithPageText(
    WidgetTester tester, String name, String pageText) async {
  final dir = await Directory.systemTemp.createTemp('o5persist');
  persistentDir = dir;
  persistentDbFile = File('${dir.path}/camscanner.sqlite');
  addTearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  final db = AppDatabase(NativeDatabase(persistentDbFile!));
  final now = DateTime.utc(2026, 7, 1, 12);
  final docId = await db.into(db.documents).insert(DocumentsCompanion.insert(
        name: name, createdAt: now, modifiedAt: now));
  await db.into(db.pages).insert(PagesCompanion.insert(
        documentId: docId,
        position: 1,
        relativeImagePath: 'documents/$docId/page_1.jpg',
        ocrText: Value(pageText)));
  await db.close();
}
