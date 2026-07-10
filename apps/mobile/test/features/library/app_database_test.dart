import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/drift/app_database.dart';

void main() {
  test('AppDatabase round-trips a document and a page in memory', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final now = DateTime.utc(2026, 6, 27, 20, 26, 42);
    final docId = await db
        .into(db.documents)
        .insert(
          DocumentsCompanion.insert(
            name: 'Scan 2026-06-27 20.26.42',
            createdAt: now,
            modifiedAt: now,
          ),
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

    final docs = await db.select(db.documents).get();
    final pages = await db.select(db.pages).get();
    expect(docs, hasLength(1));
    expect(docs.single.name, 'Scan 2026-06-27 20.26.42');
    // Compare the instant (storage-mode agnostic). With store_date_time_values_
    // as_text the readback is also UTC, so this is exact.
    expect(docs.single.createdAt.toUtc(), now);
    expect(docs.single.createdAt.isAtSameMomentAs(now), isTrue);
    expect(pages.single.documentId, docId);
    expect(pages.single.relativeImagePath, 'documents/$docId/page_1.jpg');
  });

  test(
    'deleting a document cascades to its pages (FK pragma enabled)',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final now = DateTime.utc(2026, 6, 27, 20, 26, 42);
      final docId = await db
          .into(db.documents)
          .insert(
            DocumentsCompanion.insert(
              name: 'Scan 2026-06-27 20.26.42',
              createdAt: now,
              modifiedAt: now,
            ),
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

      await (db.delete(db.documents)..where((d) => d.id.equals(docId))).go();

      final pages = await db.select(db.pages).get();
      expect(pages, isEmpty, reason: 'cascade should have removed the page');
    },
  );
}
