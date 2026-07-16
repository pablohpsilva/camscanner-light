import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/logging/app_logger.dart';
import 'package:mobile/features/library/document_file_store.dart';
import 'package:mobile/features/library/document_repository.dart';
import 'package:mobile/features/library/drift/app_database.dart';
import 'package:mobile/features/library/drift/page_dao.dart';
import 'package:mobile/features/library/ocr/ocr_engine.dart';
import 'package:mobile/features/library/ocr/ocr_result.dart';
import 'package:mobile/features/library/ocr/ocr_service.dart';

/// An engine that returns fixed text and records how many times it ran.
class _FakeEngine implements OcrEngine {
  final String text;
  int calls = 0;
  _FakeEngine(this.text);
  @override
  Future<OcrResult> recognize(Uint8List bytes) async {
    calls++;
    return OcrResult(text: text, words: const []);
  }
}

void main() {
  late AppDatabase db;
  late Directory base;
  late DocumentFileStore store;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    base = Directory.systemTemp.createTempSync('ocr_svc');
    store = DocumentFileStore(base);
  });
  tearDown(() async {
    await db.close();
    base.deleteSync(recursive: true);
  });

  OcrService service(OcrEngine engine) =>
      OcrService(db, store, PageDao(db, store), engine, SilentAppLogger());

  Future<int> seedPage() async {
    final id = await db
        .into(db.documents)
        .insert(
          DocumentsCompanion.insert(
            name: 'Doc',
            createdAt: DateTime.utc(2026, 1, 1),
            modifiedAt: DateTime.utc(2026, 1, 1),
          ),
        );
    final rel = store.relativeFor(id, 1);
    await store.writeRelative(rel, [1, 2, 3]);
    await db
        .into(db.pages)
        .insert(
          PagesCompanion.insert(
            documentId: id,
            position: 1,
            relativeImagePath: rel,
          ),
        );
    return id;
  }

  test('runOcr caches the recognized text on the page', () async {
    final id = await seedPage();
    await service(_FakeEngine('hello')).runOcr(id, 1);
    final row = await (db.select(
      db.pages,
    )..where((p) => p.documentId.equals(id))).getSingle();
    expect(row.ocrText, 'hello');
  });

  test('runOcr throws DocumentSaveException for a missing page', () async {
    final id = await seedPage();
    expect(
      () => service(_FakeEngine('x')).runOcr(id, 99),
      throwsA(isA<DocumentSaveException>()),
    );
  });

  test('trigger is a no-op for the NoOp engine', () async {
    final id = await seedPage();
    // Should not throw and should leave OCR untouched.
    service(const NoOpOcrEngine()).trigger(id, 1);
    final row = await (db.select(
      db.pages,
    )..where((p) => p.documentId.equals(id))).getSingle();
    expect(row.ocrText, isNull);
  });

  test('trigger runs a real engine (fire-and-forget)', () async {
    final id = await seedPage();
    final engine = _FakeEngine('scanned');
    service(engine).trigger(id, 1);
    // Let the fire-and-forget future settle.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(engine.calls, 1);
    final row = await (db.select(
      db.pages,
    )..where((p) => p.documentId.equals(id))).getSingle();
    expect(row.ocrText, 'scanned');
  });
}
