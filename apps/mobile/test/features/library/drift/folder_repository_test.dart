import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document.dart';
import 'package:mobile/features/library/document_file_store.dart';
import 'package:mobile/features/library/document_repository.dart';
import 'package:mobile/features/library/drift/app_database.dart' hide Document;
import 'package:mobile/features/library/drift/drift_document_repository.dart';
import 'package:mobile/features/library/jpeg_exif_scrubber.dart';
import 'package:mobile/features/library/pdf/pdf_builder.dart';
import 'package:mobile/features/scan/captured_image.dart';

import '../../../support/fake_library.dart';

void main() {
  late Directory base;
  late AppDatabase db;
  late CapturedImage capture;
  // ignore: prefer_function_declarations_over_variables
  final clock = () => DateTime.utc(2026, 6, 27, 20, 26, 42);

  setUp(() {
    base = Directory.systemTemp.createTempSync('folderrepo');
    // Opened through AppDatabase so `beforeOpen` runs `PRAGMA foreign_keys =
    // ON` — required for the deleteFolder SET-NULL FK behavior under test.
    db = AppDatabase(NativeDatabase.memory());
    final src = File('${base.path}/cap.jpg')
      ..writeAsBytesSync(
        File('test/fixtures/exif_sample.jpg').readAsBytesSync(),
      );
    capture = CapturedImage(src.path);
  });

  tearDown(() async {
    await db.close();
    if (base.existsSync()) base.deleteSync(recursive: true);
  });

  DriftDocumentRepository repo() => DriftDocumentRepository(
    db: db,
    scrubber: const JpegExifScrubber(),
    fileStore: DocumentFileStore(base),
    clock: clock,
    pdfBuilder: const PdfBuilder(),
    warper: FakeImageWarper(),
  );

  Future<Document> seedOneDoc(DriftDocumentRepository r) =>
      r.createFromCapture(capture);

  test('createFolder trims and lists name-ascending', () async {
    final r = repo();
    await r.createFolder('  Zed ');
    await r.createFolder('Alpha');
    final names = (await r.listFolders()).map((f) => f.name).toList();
    expect(names, ['Alpha', 'Zed']);
  });

  test('createFolder rejects empty name', () async {
    expect(
      () => repo().createFolder('   '),
      throwsA(isA<DocumentSaveException>()),
    );
  });

  test('moveToFolder sets folderId on the summary; null unfiles it', () async {
    final r = repo();
    final doc = await seedOneDoc(r);
    final f = await r.createFolder('Receipts');
    await r.moveToFolder(doc.id, f.id);
    expect((await r.listDocumentSummaries()).single.folderId, f.id);
    await r.moveToFolder(doc.id, null);
    expect((await r.listDocumentSummaries()).single.folderId, isNull);
  });

  test(
    'deleteFolder unfiles member documents (SET NULL), keeps the document',
    () async {
      final r = repo();
      final doc = await seedOneDoc(r);
      final f = await r.createFolder('Receipts');
      await r.moveToFolder(doc.id, f.id);
      await r.deleteFolder(f.id);
      expect(await r.listFolders(), isEmpty);
      final s = await r.listDocumentSummaries();
      expect(s.single.document.id, doc.id); // document survived
      expect(s.single.folderId, isNull); // unfiled
    },
  );

  test('renameFolder updates name; unknown id throws', () async {
    final r = repo();
    final f = await r.createFolder('Old');
    final renamed = await r.renameFolder(f.id, 'New');
    expect(renamed.name, 'New');
    expect(() => r.renameFolder(9999, 'X'), throwsA(isA<DocumentSaveException>()));
  });
}
