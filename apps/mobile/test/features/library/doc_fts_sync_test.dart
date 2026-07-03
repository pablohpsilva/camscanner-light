import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/drift/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<int> insertDoc(String name) => db.into(db.documents).insert(
      DocumentsCompanion.insert(
          name: name, createdAt: DateTime.now(), modifiedAt: DateTime.now()));

  Future<int> insertPage(int docId, int pos, {String? ocr}) =>
      db.into(db.pages).insert(PagesCompanion.insert(
            documentId: docId,
            position: pos,
            relativeImagePath: 'documents/$docId/page_$pos.jpg',
            ocrText: Value(ocr),
          ));

  // Doc ids whose concatenated OCR text matches the trigram expression.
  Future<List<int>> matchDocs(String expr) async {
    final rows = await db.customSelect(
      'SELECT rowid AS did FROM doc_fts WHERE doc_fts MATCH ?',
      variables: [Variable.withString(expr)],
    ).get();
    return rows.map((r) => r.read<int>('did')).toList();
  }

  test('multi-word AND matches across DIFFERENT pages of one document',
      () async {
    final id = await insertDoc('Report');
    await insertPage(id, 1, ocr: 'ACME corporation header');
    await insertPage(id, 3, ocr: 'final INVOICE total');
    expect(await matchDocs('"acme" AND "invoice"'), [id]);
  });

  test('trigger fills the index when ocr_text is set via UPDATE', () async {
    final id = await insertDoc('Doc');
    final pageId = await insertPage(id, 1); // ocr null → not indexed yet
    expect(await matchDocs('"keyword"'), isEmpty);
    await (db.update(db.pages)..where((t) => t.id.equals(pageId)))
        .write(const PagesCompanion(ocrText: Value('a KEYWORD here')));
    expect(await matchDocs('"keyword"'), [id]);
  });

  test('clearing ocr_text and deleting pages leaves no orphan doc_fts row',
      () async {
    final id = await insertDoc('Doc');
    final p1 = await insertPage(id, 1, ocr: 'alpha KEYWORD');
    await insertPage(id, 2, ocr: 'beta KEYWORD');
    expect(await matchDocs('"keyword"'), [id]);
    // clear one page's text → doc still matches via the other page
    await (db.update(db.pages)..where((t) => t.id.equals(p1)))
        .write(const PagesCompanion(ocrText: Value(null)));
    expect(await matchDocs('"keyword"'), [id]);
    // delete all pages → doc drops out of the index entirely
    await (db.delete(db.pages)..where((t) => t.documentId.equals(id))).go();
    expect(await matchDocs('"keyword"'), isEmpty);
  });

  test('backfill indexes pre-existing ocr_text', () async {
    final id = await insertDoc('Old');
    await insertPage(id, 1, ocr: 'legacy CONTRACT text');
    // simulate an un-indexed (pre-v5) state, then run the backfill
    await db.customStatement('DELETE FROM doc_fts');
    expect(await matchDocs('"contract"'), isEmpty);
    await db.backfillFtsForTest();
    expect(await matchDocs('"contract"'), [id]);
  });
}
