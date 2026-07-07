import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/drift/app_database.dart';

import '../support/persistent_storage.dart';

/// Usage: a saved document "Report" with page 1 text "ACME corporation" and page 3 text "final INVOICE"
Future<void>
    aSavedDocumentReportWithPage1TextAcmeCorporationAndPage3TextFinalInvoice(
        WidgetTester tester) async {
  // First Given: create the on-disk storage the app will later read (shared via
  // persistent_storage so the launch step targets the SAME database/dir).
  final dir = await Directory.systemTemp.createTemp('ftspersist');
  persistentDir = dir;
  persistentDbFile = File('${dir.path}/camscanner.sqlite');
  addTearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  final db = AppDatabase(NativeDatabase(persistentDbFile!));
  final now = DateTime.utc(2026, 7, 1, 12);
  final docId = await db.into(db.documents).insert(DocumentsCompanion.insert(
        name: 'Report', createdAt: now, modifiedAt: now));
  // The FTS index holds ONE row per document (group_concat of its pages'
  // ocr_text), so a multi-word MATCH must still find terms that live on
  // DIFFERENT pages. Seed "acme" on page 1 and "invoice" on page 3.
  await db.into(db.pages).insert(PagesCompanion.insert(
        documentId: docId,
        position: 1,
        relativeImagePath: 'documents/$docId/page_1.jpg',
        ocrText: const Value('ACME corporation')));
  await db.into(db.pages).insert(PagesCompanion.insert(
        documentId: docId,
        position: 3,
        relativeImagePath: 'documents/$docId/page_3.jpg',
        ocrText: const Value('final INVOICE')));
  await db.close();
}
