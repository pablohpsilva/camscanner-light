// On-device migration + persistence proof for folders/tags (schemaVersion 9).
//
// The host suite (fake in-memory repo, or NativeDatabase.memory() under
// libdartcv-less `flutter test`) cannot prove this: it never exercises a real
// on-disk sqlite file being closed and reopened, so it can't show that the v9
// migration (CREATE TABLE folders/tags/document_tags + ADD COLUMN
// documents.folder_id REFERENCES folders(id) ON DELETE SET NULL) actually
// persists across a fresh AppDatabase instance the way it will after a real
// app restart. This test:
//   1. Opens a brand-new AppDatabase over a temp file (fresh v9 create).
//   2. Creates a folder + a tag, a document, files it, tags it.
//   3. Closes the DB, opens a NEW AppDatabase over the SAME file (mirrors an
//      app restart) and asserts folder/tag/membership survived the reopen.
//   4. Deletes the folder and asserts the document is unfiled (not deleted) —
//      proving ON DELETE SET NULL is real on-device sqlite, not just Drift's
//      in-memory semantics.
//
// No pre-v9 fixture DB is bundled (none exists in this repo yet), so this
// exercises onCreate at schemaVersion 9 rather than onUpgrade from < 9. That
// is a named, explicit gap: it proves the v9 SCHEMA is sound on real sqlite,
// not that the onUpgrade migration path from an older on-disk DB is bug-free.
//
// Run: flutter test integration_test/org_migration_device_test.dart -d <id>
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile/features/library/document_file_store.dart';
import 'package:mobile/features/library/drift/app_database.dart';
import 'package:mobile/features/library/drift/drift_document_repository.dart';
import 'package:mobile/features/library/hybrid_warper.dart';
import 'package:mobile/features/library/jpeg_exif_scrubber.dart';
import 'package:mobile/features/library/pdf/pdf_builder.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'folder/tag/membership survive a DB reopen and folder-delete unfiles (SET NULL) on real sqlite',
    (tester) async {
      final baseDir = await Directory.systemTemp.createTemp('org_migration');
      final dbFile = File('${baseDir.path}/camscanner.sqlite');
      addTearDown(() async {
        if (await baseDir.exists()) await baseDir.delete(recursive: true);
      });

      DriftDocumentRepository repoFor(AppDatabase db) => DriftDocumentRepository(
        db: db,
        scrubber: const JpegExifScrubber(),
        fileStore: DocumentFileStore(baseDir),
        clock: DateTime.now,
        pdfBuilder: const PdfBuilder(),
        warper: const HybridWarper(),
      );

      late int documentId;
      late int folderId;
      late int tagId;

      // --- SESSION 1: create + file + tag, over a real on-disk sqlite file ---
      // Opened directly on the root isolate (NativeDatabase(file), not
      // createInBackground / Isolate.spawn) — see openAppDatabase's doc comment:
      // native-asset sqlite3 symbol resolution is unreliable in a spawned
      // isolate and hangs the app on "opens but never loads".
      {
        final db = AppDatabase(openAppDatabase(dbFile));
        final repo = repoFor(db);

        final folder = await repo.createFolder('Taxes');
        folderId = folder.id;
        final tag = await repo.createTag('Important');
        tagId = tag.id;

        // Insert a minimal document + page directly through the DB rather than
        // createFromCapture: createFromCapture needs a real decodable JPEG (it
        // scrubs EXIF and runs the page processor), which adds native-pipeline
        // risk unrelated to what this test is proving (schema persistence, not
        // capture). A direct row insert is the simpler, reliable path — mirrors
        // the existing fts_search_device_test.dart / o5_content_search_device_test.dart
        // pattern for the same reason.
        final now = DateTime.now();
        documentId = await db
            .into(db.documents)
            .insert(
              DocumentsCompanion.insert(name: 'Receipt', createdAt: now, modifiedAt: now),
            );
        await db
            .into(db.pages)
            .insert(
              PagesCompanion.insert(
                documentId: documentId,
                position: 1,
                relativeImagePath: 'documents/$documentId/page_1.jpg',
              ),
            );

        await repo.moveToFolder(documentId, folderId);
        await repo.setDocumentTags(documentId, {tagId});

        // Sanity check within the same session before we close it.
        final summaries = await repo.listDocumentSummaries();
        final receipt = summaries.singleWhere((s) => s.document.id == documentId);
        expect(receipt.folderId, folderId);
        expect(receipt.tags.map((t) => t.id), [tagId]);

        await db.close();
      }

      // --- SESSION 2: brand-new AppDatabase over the SAME file (mirrors a  ---
      // --- real app restart) — proves persistence, not in-memory caching. ---
      {
        final db = AppDatabase(openAppDatabase(dbFile));
        final repo = repoFor(db);

        final folders = await repo.listFolders();
        expect(folders.map((f) => f.id), contains(folderId));
        expect(folders.singleWhere((f) => f.id == folderId).name, 'Taxes');

        final tags = await repo.listTags();
        expect(tags.map((t) => t.id), contains(tagId));
        expect(tags.singleWhere((t) => t.id == tagId).name, 'Important');

        final docTags = await repo.tagsForDocument(documentId);
        expect(docTags.map((t) => t.id), [tagId]);

        final summaries = await repo.listDocumentSummaries();
        final receipt = summaries.singleWhere((s) => s.document.id == documentId);
        expect(receipt.folderId, folderId);
        expect(receipt.tags.map((t) => t.id), [tagId]);

        // --- Deleting the folder must unfile (SET NULL), never delete, the ---
        // --- document. This is the real assertion that ON DELETE SET NULL  --
        // --- fires on real sqlite (foreign_keys pragma is ON in beforeOpen) --
        // --- rather than only in Drift's in-memory/mocked semantics.       --
        await repo.deleteFolder(folderId);

        final afterDelete = await repo.listDocumentSummaries();
        final receiptAfterDelete = afterDelete.singleWhere(
          (s) => s.document.id == documentId,
        );
        expect(receiptAfterDelete.folderId, isNull);
        // Tag membership is independent of folder membership and must survive.
        expect(receiptAfterDelete.tags.map((t) => t.id), [tagId]);

        final foldersAfterDelete = await repo.listFolders();
        expect(foldersAfterDelete.map((f) => f.id), isNot(contains(folderId)));

        await db.close();
      }
    },
  );
}
