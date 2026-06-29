import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/library/drift/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

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
    raw.execute("INSERT INTO documents (id, name, created_at, modified_at) "
        "VALUES (1, 'Scan old', '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z');");
    raw.execute("INSERT INTO pages (id, document_id, position, relative_image_path) "
        "VALUES (1, 1, 1, '1/1.jpg');");
    raw.execute('PRAGMA user_version = 1;');
    raw.close();

    // 2) Open the real (v2) AppDatabase on the same file -> triggers onUpgrade.
    final db = AppDatabase(NativeDatabase(file));

    // 3a) The corners column exists and the legacy row reads back null.
    final rows = await db.select(db.pages).get();
    expect(rows, hasLength(1));
    expect(rows.single.corners, isNull);
    expect(CropCorners.tryParse(rows.single.corners) ?? CropCorners.fullFrame,
        CropCorners.fullFrame);

    // 3b) A fresh corners write round-trips.
    await (db.update(db.pages)..where((t) => t.id.equals(1)))
        .write(PagesCompanion(corners: Value(CropCorners.fullFrame.toStorage())));
    final updated = await (db.select(db.pages)..where((t) => t.id.equals(1))).getSingle();
    expect(CropCorners.tryParse(updated.corners), CropCorners.fullFrame);

    await db.close();
    await dir.delete(recursive: true);
  });
}
