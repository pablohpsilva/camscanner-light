import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/drift/app_database.dart';

import '../support/persistent_storage.dart';

/// Usage: a saved document "Decoy" with page 1 text "acme only, nothing else"
Future<void> aSavedDocumentDecoyWithPage1TextAcmeOnlyNothingElse(
    WidgetTester tester) async {
  // Reuses the SAME storage the preceding step created, so both documents live
  // in one database — the search must return "Report" and exclude this decoy
  // (it has "acme" but not "invoice").
  final db = AppDatabase(NativeDatabase(persistentDbFile!));
  final now = DateTime.utc(2026, 7, 1, 12, 1);
  final docId = await db.into(db.documents).insert(DocumentsCompanion.insert(
        name: 'Decoy', createdAt: now, modifiedAt: now));
  await db.into(db.pages).insert(PagesCompanion.insert(
        documentId: docId,
        position: 1,
        relativeImagePath: 'documents/$docId/page_1.jpg',
        ocrText: const Value('acme only, nothing else')));
  await db.close();
}
