// On-device BDD — multi-word FTS5 search spanning pages.
//
// Scenario: a two-word query whose words live on DIFFERENT pages of one
// document ("Report") still finds that document; a second document ("Decoy")
// that contains only one of the words is excluded.
//
// Run: flutter test integration_test/fts_search_device_test.dart -d RZCY51D0T1K
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile/features/library/drift/app_database.dart';
import 'package:mobile/main.dart' as app;

import '../test/support/fake_library.dart';
import '../test/support/fake_scan.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('multi-word search spanning pages finds "Report" and excludes "Decoy"', (
    tester,
  ) async {
    // --- SEED ----------------------------------------------------------------
    // Write two documents to a real on-device SQLite file so the v5 migration
    // (FTS5 trigram table + triggers) runs before the app opens the same file.
    final baseDir = await Directory.systemTemp.createTemp('fts_search');
    final dbFile = File('${baseDir.path}/camscanner.sqlite');
    addTearDown(() async {
      if (await baseDir.exists()) await baseDir.delete(recursive: true);
    });

    {
      final db = AppDatabase(NativeDatabase(dbFile));
      final now = DateTime.now();

      // "Report": two pages on different positions — the FTS trigger rebuilds
      // a single doc_fts row with both pages' text concatenated, so the AND
      // query "acme AND invoice" matches across pages.
      final reportId = await db
          .into(db.documents)
          .insert(
            DocumentsCompanion.insert(
              name: 'Report',
              createdAt: now,
              modifiedAt: now,
            ),
          );
      await db
          .into(db.pages)
          .insert(
            PagesCompanion.insert(
              documentId: reportId,
              position: 1,
              relativeImagePath: 'documents/$reportId/page_1.jpg',
              ocrText: const Value('ACME corporation'),
            ),
          );
      await db
          .into(db.pages)
          .insert(
            PagesCompanion.insert(
              documentId: reportId,
              position: 3,
              relativeImagePath: 'documents/$reportId/page_3.jpg',
              ocrText: const Value('final INVOICE'),
            ),
          );

      // "Decoy": only one of the query words — must not appear in results.
      final decoyId = await db
          .into(db.documents)
          .insert(
            DocumentsCompanion.insert(
              name: 'Decoy',
              createdAt: now,
              modifiedAt: now,
            ),
          );
      await db
          .into(db.pages)
          .insert(
            PagesCompanion.insert(
              documentId: decoyId,
              position: 1,
              relativeImagePath: 'documents/$decoyId/page_1.jpg',
              ocrText: const Value('acme only, nothing else'),
            ),
          );

      await db.close();
    }

    // --- LAUNCH APP reading that same storage --------------------------------
    // persistentLibraryDependencies opens the SAME db file, so the real
    // searchDocuments / FTS5 index is live when the HomeScreen renders.
    app.runCamScannerApp(
      scanDependencies: grantedScanDependencies(),
      libraryDependencies: persistentLibraryDependencies(
        dbFile: dbFile,
        baseDir: baseDir,
      ),
    );
    // Bounded settle: let the DB open + home screen render without risk of
    // hanging forever on a perpetual loading spinner (Key('documents-loading')).
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    // --- SEARCH --------------------------------------------------------------
    // The Ream search field is always visible in the header (no icon to open).
    await tester.enterText(
      find.byKey(const Key('documents-search-field')),
      'acme invoice',
    );
    // Bounded settle: wait for FTS query results to render.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    // --- ASSERT --------------------------------------------------------------
    expect(find.text('Report'), findsOneWidget);
    expect(find.text('Decoy'), findsNothing);
  });
}
