import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/drift/app_database.dart';

void main() {
  test('schemaVersion is 8', () {
    final db = AppDatabase(NativeDatabase.memory());
    expect(db.schemaVersion, 8);
    addTearDown(db.close);
  });

  test('rotationQuarterTurns defaults to 0 on insert without it', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final now = DateTime.now();
    final docId = await db
        .into(db.documents)
        .insert(
          DocumentsCompanion.insert(name: 'D', createdAt: now, modifiedAt: now),
        );
    await db
        .into(db.pages)
        .insert(
          PagesCompanion.insert(
            documentId: docId,
            position: 1,
            relativeImagePath: 'documents/$docId/page_1.jpg',
          ),
        );
    final page = await (db.select(
      db.pages,
    )..where((t) => t.documentId.equals(docId))).getSingle();
    expect(page.rotationQuarterTurns, 0);
  });

  test('enhancerMode defaults to 0 (none) on insert without it', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final now = DateTime.now();
    final docId = await db
        .into(db.documents)
        .insert(
          DocumentsCompanion.insert(name: 'D', createdAt: now, modifiedAt: now),
        );
    await db
        .into(db.pages)
        .insert(
          PagesCompanion.insert(
            documentId: docId,
            position: 1,
            relativeImagePath: 'documents/$docId/page_1.jpg',
          ),
        );
    final page = await (db.select(
      db.pages,
    )..where((t) => t.documentId.equals(docId))).getSingle();
    expect(page.enhancerMode, 0);
  });
}
