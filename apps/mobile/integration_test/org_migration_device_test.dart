// On-device migration + persistence proof for folders/tags (schemaVersion 9).
//
// The host suite (fake in-memory repo, or NativeDatabase.memory() under
// libdartcv-less `flutter test`) cannot prove this: it never exercises a real
// on-disk sqlite file being closed and reopened, so it can't show that the v9
// migration (CREATE TABLE folders/tags/document_tags + ADD COLUMN
// documents.folder_id REFERENCES folders(id) ON DELETE SET NULL) actually
// persists across a fresh AppDatabase instance the way it will after a real
// app restart. The first test below:
//   1. Opens a brand-new AppDatabase over a temp file (fresh v9 create).
//   2. Creates a folder + a tag, a document, files it, tags it.
//   3. Closes the DB, opens a NEW AppDatabase over the SAME file (mirrors an
//      app restart) and asserts folder/tag/membership survived the reopen.
//   4. Deletes the folder and asserts the document is unfiled (not deleted) —
//      proving ON DELETE SET NULL is real on-device sqlite, not just Drift's
//      in-memory semantics.
//
// That first test only exercises onCreate at schemaVersion 9 (a brand-new DB
// file), not the onUpgrade path an existing installed app actually takes. The
// second test below closes that gap: it builds a real v8-shaped sqlite file
// by hand (mirroring test/features/library/drift/migration_test.dart's
// _buildV8Db), inserts a pre-migration row, then opens it through the
// production AppDatabase to trigger the v8->v9 onUpgrade step on real
// on-device sqlite (not NativeDatabase.memory(), not the host-only libdartcv-
// less environment) — proving the ADD COLUMN / CREATE TABLE / ON DELETE
// SET NULL migration is sound against a real on-disk file, not just against a
// freshly created one.
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
import 'package:sqlite3/sqlite3.dart' as sqlite;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Creates the v8-shaped documents + pages tables (documents.is_id_card,
/// pages through enhancer_mode) plus the FTS vtable + triggers, then sets
/// PRAGMA user_version = 8. Mirrors the real v8 shape so the v8->v9 step
/// (folders/tags/document_tags + documents.folder_id) starts from a faithful
/// pre-migration DB. Copied from
/// test/features/library/drift/migration_test.dart's `_buildV8Db` so this
/// device test does not depend on host-only test sources.
void _buildV8Db(sqlite.Database raw) {
  raw.execute('''
    CREATE TABLE documents (
      id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      created_at TEXT NOT NULL,
      modified_at TEXT NOT NULL,
      is_id_card INTEGER NOT NULL DEFAULT 0
    );
  ''');
  raw.execute('''
    CREATE TABLE pages (
      id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      document_id INTEGER NOT NULL REFERENCES documents (id) ON DELETE CASCADE,
      position INTEGER NOT NULL,
      relative_image_path TEXT NOT NULL,
      corners TEXT,
      flat_relative_path TEXT,
      rotation_quarter_turns INTEGER NOT NULL DEFAULT 0,
      enhancer_mode INTEGER NOT NULL DEFAULT 0,
      ocr_text TEXT,
      ocr_boxes TEXT
    );
  ''');
  raw.execute(
    "CREATE VIRTUAL TABLE doc_fts USING fts5(text, tokenize = 'trigram')",
  );
  raw.execute(
    "CREATE TRIGGER doc_fts_ai AFTER INSERT ON pages "
    "WHEN NEW.ocr_text IS NOT NULL BEGIN "
    "DELETE FROM doc_fts WHERE rowid = NEW.document_id; "
    "INSERT INTO doc_fts(rowid, text) "
    "SELECT document_id, group_concat(ocr_text, ' ') FROM pages "
    "WHERE document_id = NEW.document_id AND ocr_text IS NOT NULL "
    "GROUP BY document_id; END",
  );
  raw.execute(
    "CREATE TRIGGER doc_fts_au AFTER UPDATE OF ocr_text ON pages "
    "BEGIN "
    "DELETE FROM doc_fts WHERE rowid = NEW.document_id; "
    "INSERT INTO doc_fts(rowid, text) "
    "SELECT document_id, group_concat(ocr_text, ' ') FROM pages "
    "WHERE document_id = NEW.document_id AND ocr_text IS NOT NULL "
    "GROUP BY document_id; END",
  );
  raw.execute(
    "CREATE TRIGGER doc_fts_ad AFTER DELETE ON pages "
    "BEGIN "
    "DELETE FROM doc_fts WHERE rowid = OLD.document_id; "
    "INSERT INTO doc_fts(rowid, text) "
    "SELECT document_id, group_concat(ocr_text, ' ') FROM pages "
    "WHERE document_id = OLD.document_id AND ocr_text IS NOT NULL "
    "GROUP BY document_id; END",
  );
  raw.execute('PRAGMA user_version = 8;');
}

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

  testWidgets(
    'v8 -> v9 onUpgrade adds folders/tags/document_tags + folder_id on a real '
    'pre-existing sqlite file, and ON DELETE SET NULL fires post-migration',
    (tester) async {
      final baseDir = await Directory.systemTemp.createTemp(
        'org_migration_v8upgrade',
      );
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

      // --- Build a real v8-shaped sqlite file on disk (raw SQL, no Drift) ---
      // --- and seed it with a pre-migration document + page row, mirroring ---
      // --- what an actual installed app's DB looks like before this update. ---
      final raw = sqlite.sqlite3.open(dbFile.path);
      _buildV8Db(raw);
      raw.execute(
        "INSERT INTO documents (id, name, created_at, modified_at, is_id_card) "
        "VALUES (1, 'Legacy Receipt', '2026-01-01T00:00:00.000Z', "
        "'2026-01-01T00:00:00.000Z', 0);",
      );
      raw.execute(
        "INSERT INTO pages (id, document_id, position, relative_image_path) "
        "VALUES (1, 1, 1, 'documents/1/page_1.jpg');",
      );
      raw.close();

      // --- Open through the production AppDatabase: on-disk user_version is ---
      // --- 8, schemaVersion is 9, so this triggers real onUpgrade(from: 8, ---
      // --- to: 9) against actual on-device sqlite (not NativeDatabase.memory()). ---
      final db = AppDatabase(openAppDatabase(dbFile));
      final repo = repoFor(db);

      // The pre-existing row survived the migration untouched.
      final docsAfterUpgrade = await db.select(db.documents).get();
      expect(docsAfterUpgrade, hasLength(1));
      final legacyDoc = docsAfterUpgrade.single;
      expect(legacyDoc.name, 'Legacy Receipt');
      // folder_id is a net-new nullable column added by the v8->v9 step; a
      // pre-migration row must read back with it null, not fail to load.
      expect(legacyDoc.folderId, isNull);

      // --- folders/tags/document_tags are net-new in v9. Using them here ---
      // --- proves onUpgrade actually CREATEd the tables (not just onCreate ---
      // --- for a brand-new DB, which the first test in this file covers). ---
      final folder = await repo.createFolder('Taxes');
      final tag = await repo.createTag('Important');
      await repo.moveToFolder(legacyDoc.id, folder.id);
      await repo.setDocumentTags(legacyDoc.id, {tag.id});

      final filed = await repo.listDocumentSummaries();
      final filedReceipt = filed.singleWhere((s) => s.document.id == legacyDoc.id);
      expect(filedReceipt.folderId, folder.id);
      expect(filedReceipt.tags.map((t) => t.id), [tag.id]);

      // --- Deleting the folder must unfile (SET NULL), never delete, the ---
      // --- document — proving ON DELETE SET NULL fires on real on-device ---
      // --- sqlite reached via the onUpgrade path, not only via onCreate. ---
      await repo.deleteFolder(folder.id);

      final afterDelete = await repo.listDocumentSummaries();
      final receiptAfterDelete = afterDelete.singleWhere(
        (s) => s.document.id == legacyDoc.id,
      );
      expect(receiptAfterDelete.folderId, isNull);
      // Tag membership is independent of folder membership and must survive.
      expect(receiptAfterDelete.tags.map((t) => t.id), [tag.id]);

      await db.close();
    },
  );
}
