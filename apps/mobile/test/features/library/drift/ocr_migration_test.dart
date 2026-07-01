import 'dart:io';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/drift/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  test('v3→v4: upgrading adds nullable Pages.ocrText and ocrBoxes', () async {
    final dir = await Directory.systemTemp.createTemp('ocrmig_v3v4');
    final file = File('${dir.path}/app.db');

    // Build a v3-shaped DB (corners + flatRelativePath, no OCR columns).
    final raw = sqlite.sqlite3.open(file.path);
    raw.execute('''
      CREATE TABLE documents (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL, created_at TEXT NOT NULL, modified_at TEXT NOT NULL);
    ''');
    raw.execute('''
      CREATE TABLE pages (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        document_id INTEGER NOT NULL REFERENCES documents (id),
        position INTEGER NOT NULL, relative_image_path TEXT NOT NULL,
        corners TEXT, flat_relative_path TEXT);
    ''');
    raw.execute("INSERT INTO documents VALUES "
        "(1,'Scan','2026-01-01T00:00:00.000Z','2026-01-01T00:00:00.000Z');");
    raw.execute("INSERT INTO pages (id,document_id,position,relative_image_path) "
        "VALUES (1,1,1,'1/1.jpg');");
    raw.execute('PRAGMA user_version = 3;');
    raw.close();

    // Open at v4 → triggers onUpgrade.
    final db = AppDatabase(NativeDatabase(file));
    final rows = await db.select(db.pages).get();
    expect(rows.single.ocrText, isNull);
    expect(rows.single.ocrBoxes, isNull);

    // Fresh write round-trips.
    await (db.update(db.pages)..where((t) => t.id.equals(1))).write(
        const PagesCompanion(
            ocrText: Value('HELLO'), ocrBoxes: Value('[]')));
    final updated =
        await (db.select(db.pages)..where((t) => t.id.equals(1))).getSingle();
    expect(updated.ocrText, 'HELLO');
    expect(updated.ocrBoxes, '[]');

    await db.close();
    await dir.delete(recursive: true);
  });
}
