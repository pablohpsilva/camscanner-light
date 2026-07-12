import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/library/drift/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Creates the v5-shaped documents + pages tables (no is_id_card column)
/// including the FTS virtual table and triggers that were added in v4/v5, then
/// sets PRAGMA user_version = 5.  The FTS table is required because the
/// onUpgrade path only calls _createFts() when from < 5; skipping it would
/// make the v5→v6 step leave the DB without the trigger set.
void _buildV5Db(sqlite.Database raw) {
  raw.execute('''
    CREATE TABLE documents (
      id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      created_at TEXT NOT NULL,
      modified_at TEXT NOT NULL
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
  raw.execute('PRAGMA user_version = 5;');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('upgrading a v1 database adds the nullable Pages.corners column', () async {
    final dir = await Directory.systemTemp.createTemp('e1mig');
    final file = File('${dir.path}/app.db');

    // 1) Build a v1-shaped DB by raw SQL (pages WITHOUT corners), version 1.
    final raw = sqlite.sqlite3.open(file.path);
    raw.execute('''
      CREATE TABLE documents (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        created_at TEXT NOT NULL,
        modified_at TEXT NOT NULL
      );
    ''');
    raw.execute('''
      CREATE TABLE pages (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        document_id INTEGER NOT NULL REFERENCES documents (id) ON DELETE CASCADE,
        position INTEGER NOT NULL,
        relative_image_path TEXT NOT NULL
      );
    ''');
    raw.execute(
      "INSERT INTO documents (id, name, created_at, modified_at) "
      "VALUES (1, 'Scan old', '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z');",
    );
    raw.execute(
      "INSERT INTO pages (id, document_id, position, relative_image_path) "
      "VALUES (1, 1, 1, '1/1.jpg');",
    );
    raw.execute('PRAGMA user_version = 1;');
    raw.close();

    // 2) Open the real (v2) AppDatabase on the same file -> triggers onUpgrade.
    final db = AppDatabase(NativeDatabase(file));

    // 3a) The corners column exists and the legacy row reads back null.
    final rows = await db.select(db.pages).get();
    expect(rows, hasLength(1));
    expect(rows.single.corners, isNull);
    expect(
      CropCorners.tryParse(rows.single.corners) ?? CropCorners.fullFrame,
      CropCorners.fullFrame,
    );

    // 3b) A fresh corners write round-trips.
    await (db.update(db.pages)..where((t) => t.id.equals(1))).write(
      PagesCompanion(corners: Value(CropCorners.fullFrame.toStorage())),
    );
    final updated = await (db.select(
      db.pages,
    )..where((t) => t.id.equals(1))).getSingle();
    expect(CropCorners.tryParse(updated.corners), CropCorners.fullFrame);

    await db.close();
    await dir.delete(recursive: true);
  });

  test('v2→v3: upgrading adds nullable Pages.flatRelativePath column', () async {
    final dir = await Directory.systemTemp.createTemp('e2mig_v2v3');
    final file = File('${dir.path}/app.db');

    // Build a v2-shaped DB (has corners, no flatRelativePath).
    final raw = sqlite.sqlite3.open(file.path);
    raw.execute('''
      CREATE TABLE documents (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        created_at TEXT NOT NULL,
        modified_at TEXT NOT NULL
      );
    ''');
    raw.execute('''
      CREATE TABLE pages (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        document_id INTEGER NOT NULL REFERENCES documents (id),
        position INTEGER NOT NULL,
        relative_image_path TEXT NOT NULL,
        corners TEXT
      );
    ''');
    raw.execute(
      "INSERT INTO documents VALUES (1,'Scan','2026-01-01T00:00:00.000Z','2026-01-01T00:00:00.000Z');",
    );
    raw.execute(
      "INSERT INTO pages (id,document_id,position,relative_image_path,corners) "
      "VALUES (1,1,1,'1/1.jpg',NULL);",
    );
    raw.execute('PRAGMA user_version = 2;');
    raw.close();

    // Open at v3 → triggers onUpgrade.
    final db = AppDatabase(NativeDatabase(file));
    final rows = await db.select(db.pages).get();
    expect(rows.single.flatRelativePath, isNull);

    // Fresh write of flatRelativePath round-trips.
    await (db.update(db.pages)..where((t) => t.id.equals(1))).write(
      const PagesCompanion(flatRelativePath: Value('1/1_flat.jpg')),
    );
    final updated = await (db.select(
      db.pages,
    )..where((t) => t.id.equals(1))).getSingle();
    expect(updated.flatRelativePath, '1/1_flat.jpg');

    await db.close();
    await dir.delete(recursive: true);
  });

  test(
    'v1→v3 (cumulative): both corners and flatRelativePath columns added',
    () async {
      final dir = await Directory.systemTemp.createTemp('e2mig_v1v3');
      final file = File('${dir.path}/app.db');

      // Build a v1-shaped DB (no corners, no flatRelativePath).
      final raw = sqlite.sqlite3.open(file.path);
      raw.execute('''
      CREATE TABLE documents (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        created_at TEXT NOT NULL,
        modified_at TEXT NOT NULL
      );
    ''');
      raw.execute('''
      CREATE TABLE pages (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        document_id INTEGER NOT NULL REFERENCES documents (id),
        position INTEGER NOT NULL,
        relative_image_path TEXT NOT NULL
      );
    ''');
      raw.execute(
        "INSERT INTO documents VALUES (1,'Old','2026-01-01T00:00:00.000Z','2026-01-01T00:00:00.000Z');",
      );
      raw.execute(
        "INSERT INTO pages (id,document_id,position,relative_image_path) VALUES (1,1,1,'1/1.jpg');",
      );
      raw.execute('PRAGMA user_version = 1;');
      raw.close();

      // Open at v3 → runs both migration steps.
      final db = AppDatabase(NativeDatabase(file));
      final rows = await db.select(db.pages).get();
      expect(rows.single.corners, isNull);
      expect(rows.single.flatRelativePath, isNull);
      expect(
        CropCorners.tryParse(rows.single.corners) ?? CropCorners.fullFrame,
        CropCorners.fullFrame,
      );

      await db.close();
      await dir.delete(recursive: true);
    },
  );

  // ---------------------------------------------------------------------------
  // v5 → v6 : Documents.isIdCard column
  // ---------------------------------------------------------------------------

  test('schemaVersion is 7', () {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    expect(db.schemaVersion, 7);
  });

  test('fresh DB has the isIdCard column defaulting to false', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final id = await db
        .into(db.documents)
        .insert(
          DocumentsCompanion.insert(
            name: 'Doc',
            createdAt: DateTime.utc(2026, 7, 8),
            modifiedAt: DateTime.utc(2026, 7, 8),
          ),
        );
    final row = await (db.select(
      db.documents,
    )..where((d) => d.id.equals(id))).getSingle();
    expect(row.isIdCard, isFalse);
  });

  test(
    'v5→v6: upgrading adds Documents.is_id_card defaulting to false',
    () async {
      final dir = await Directory.systemTemp.createTemp('idmig_v5v6');
      final file = File('${dir.path}/app.db');

      // 1) Build a v5-shaped DB without is_id_card.
      final raw = sqlite.sqlite3.open(file.path);
      _buildV5Db(raw);
      raw.execute(
        "INSERT INTO documents (id, name, created_at, modified_at) "
        "VALUES (1, 'Old Doc', '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z');",
      );
      raw.close();

      // 2) Open at v6 → triggers onUpgrade (from=5, adds is_id_card).
      final db = AppDatabase(NativeDatabase(file));

      // 3a) Legacy row reads back false (column default).
      final rows = await db.select(db.documents).get();
      expect(rows, hasLength(1));
      expect(rows.single.isIdCard, isFalse);

      // 3b) A fresh isIdCard=true write round-trips.
      await (db.update(db.documents)..where((d) => d.id.equals(1))).write(
        const DocumentsCompanion(isIdCard: Value(true)),
      );
      final updated = await (db.select(
        db.documents,
      )..where((d) => d.id.equals(1))).getSingle();
      expect(updated.isIdCard, isTrue);

      await db.close();
      await dir.delete(recursive: true);
    },
  );
}
