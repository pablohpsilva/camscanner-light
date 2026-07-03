import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

part 'app_database.g.dart';

/// One scanned document's metadata. Image bytes live on disk (see Pages); this
/// table holds only metadata. `createdAt`/`modifiedAt` are stored UTC.
class Documents extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get modifiedAt => dateTime()();
}

/// One page of a document. B1 creates exactly one page (position 1). The image
/// path is RELATIVE to the app documents dir (resolved at read time) — never
/// absolute (iOS container GUID changes on reinstall/update).
class Pages extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get documentId =>
      integer().references(Documents, #id, onDelete: KeyAction.cascade)();
  IntColumn get position => integer()();
  TextColumn get relativeImagePath => text()();

  /// Normalized crop quad (E1) as "x0,y0,...,x3,y3"; null = uncropped (full
  /// frame). See CropCorners.
  TextColumn get corners => text().nullable()();

  /// Perspective-flattened image path (E2), relative to the app documents dir;
  /// null until the flatten step has been run for this page.
  TextColumn get flatRelativePath => text().nullable()();

  /// Recognized OCR text for this page (O1); null until OCR has run.
  TextColumn get ocrText => text().nullable()();

  /// JSON-encoded OCR word boxes (OcrResult.encodeBoxes); null until OCR has run.
  TextColumn get ocrBoxes => text().nullable()();
}

@DriftDatabase(tables: [Documents, Pages])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _createFts();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) await m.addColumn(pages, pages.corners);
          if (from < 3) await m.addColumn(pages, pages.flatRelativePath);
          if (from < 4) {
            await m.addColumn(pages, pages.ocrText);
            await m.addColumn(pages, pages.ocrBoxes);
          }
          if (from < 5) {
            await _createFts();
            await _backfillFts();
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  /// Trigram FTS index over each DOCUMENT's concatenated page OCR text, plus the
  /// triggers that rebuild a document's row on any page ocr_text change. Raw SQL
  /// (the vtable is not a drift table), so it runs in BOTH onCreate and onUpgrade.
  /// One row per document — a multi-word MATCH (AND) must see all terms in one
  /// row, so terms spread across a document's pages still match.
  Future<void> _createFts() async {
    await customStatement(
        "CREATE VIRTUAL TABLE doc_fts USING fts5(text, tokenize = 'trigram')");
    // group_concat over a document's non-null pages; GROUP BY makes the SELECT
    // yield zero rows when none remain, so the row is dropped (no NULL insert).
    const rebuildNew = "DELETE FROM doc_fts WHERE rowid = NEW.document_id; "
        "INSERT INTO doc_fts(rowid, text) "
        "SELECT document_id, group_concat(ocr_text, ' ') FROM pages "
        "WHERE document_id = NEW.document_id AND ocr_text IS NOT NULL "
        "GROUP BY document_id;";
    const rebuildOld = "DELETE FROM doc_fts WHERE rowid = OLD.document_id; "
        "INSERT INTO doc_fts(rowid, text) "
        "SELECT document_id, group_concat(ocr_text, ' ') FROM pages "
        "WHERE document_id = OLD.document_id AND ocr_text IS NOT NULL "
        "GROUP BY document_id;";
    await customStatement(
        "CREATE TRIGGER doc_fts_ai AFTER INSERT ON pages "
        "WHEN NEW.ocr_text IS NOT NULL BEGIN $rebuildNew END");
    await customStatement(
        "CREATE TRIGGER doc_fts_au AFTER UPDATE OF ocr_text ON pages "
        "BEGIN $rebuildNew END");
    await customStatement(
        "CREATE TRIGGER doc_fts_ad AFTER DELETE ON pages "
        "BEGIN $rebuildOld END");
  }

  /// One-time population for documents whose pages already had ocr_text pre-v5.
  Future<void> _backfillFts() async {
    await customStatement(
        "INSERT INTO doc_fts(rowid, text) "
        "SELECT document_id, group_concat(ocr_text, ' ') FROM pages "
        "WHERE ocr_text IS NOT NULL GROUP BY document_id");
  }

  /// Test-only hook to exercise the backfill statement in isolation.
  @visibleForTesting
  Future<void> backfillFtsForTest() => _backfillFts();
}

/// Production opener — lazily opens the SQLite file in a background isolate.
LazyDatabase openAppDatabase(File file) =>
    LazyDatabase(() async => NativeDatabase.createInBackground(file));
