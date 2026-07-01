import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile/features/library/document_file_store.dart';
import 'package:mobile/features/library/document_repository.dart';
import 'package:mobile/features/library/drift/app_database.dart';
import 'package:mobile/features/library/drift/drift_document_repository.dart';
import 'package:mobile/features/library/hybrid_warper.dart';
import 'package:mobile/features/library/jpeg_exif_scrubber.dart';
import 'package:mobile/features/library/ocr/ocr_result.dart';
import 'package:mobile/features/library/pdf/pdf_builder.dart';

void main() {
  late AppDatabase db;
  late DriftDocumentRepository repo;
  late DocumentFileStore store;
  late Directory base;

  setUp(() async {
    base = await Directory.systemTemp.createTemp('k1rot');
    db = AppDatabase(NativeDatabase.memory());
    store = DocumentFileStore(base);
    repo = DriftDocumentRepository(
      db: db,
      scrubber: const JpegExifScrubber(),
      fileStore: store,
      clock: DateTime.now,
      pdfBuilder: const PdfBuilder(),
      warper: const HybridWarper(),
    );
  });

  tearDown(() async {
    await db.close();
    if (await base.exists()) await base.delete(recursive: true);
  });

  test('rotates the display image (dims swap) and the cached boxes', () async {
    final now = DateTime.now();
    final id = await db.into(db.documents).insert(
        DocumentsCompanion.insert(name: 'Doc', createdAt: now, modifiedAt: now));
    // 40x20 (non-square) JPEG so a dims-swap is observable.
    final jpeg = Uint8List.fromList(
        img.encodeJpg(img.Image(width: 40, height: 20), quality: 95));
    final rel = 'documents/$id/page_1.jpg';
    await store.writeRelative(rel, jpeg);
    const box = OcrWordBox(text: 'hi', left: 0.0, top: 0.0, right: 0.2, bottom: 0.1);
    await db.into(db.pages).insert(PagesCompanion.insert(
          documentId: id,
          position: 1,
          relativeImagePath: rel,
          ocrText: const Value('hi'),
          ocrBoxes: Value(const OcrResult(text: 'hi', words: [box]).encodeBoxes()),
        ));

    await repo.rotatePage(id, 1);

    final pages = await repo.getDocumentPages(id);
    final page = pages.single;
    // Flat now exists and is the rotated (dims-swapped) image.
    expect(page.flatImagePath, isNotNull);
    final decoded = img.decodeImage(File(page.flatImagePath!).readAsBytesSync())!;
    expect(decoded.width, 20);
    expect(decoded.height, 40);
    // Box rotated CW: (0,0,0.2,0.1) -> (0.9, 0, 1.0, 0.2).
    final r = page.ocrWords.single;
    expect(r.left, closeTo(0.9, 1e-6));
    expect(r.top, closeTo(0.0, 1e-6));
    expect(r.right, closeTo(1.0, 1e-6));
    expect(r.bottom, closeTo(0.2, 1e-6));
    expect(page.ocrText, 'hi'); // text unchanged
  });

  test('throws when the page row is missing', () async {
    expect(() => repo.rotatePage(999, 1), throwsA(isA<DocumentSaveException>()));
  });

  test('throws when the image bytes are undecodable', () async {
    final now = DateTime.now();
    final id = await db.into(db.documents).insert(
        DocumentsCompanion.insert(name: 'Doc', createdAt: now, modifiedAt: now));
    final rel = 'documents/$id/page_1.jpg';
    // Write non-image bytes — img.decodeImage will return null.
    await store.writeRelative(rel, Uint8List.fromList([0, 0, 0, 0]));
    await db.into(db.pages).insert(PagesCompanion.insert(
          documentId: id,
          position: 1,
          relativeImagePath: rel,
        ));

    expect(
      () => repo.rotatePage(id, 1),
      throwsA(isA<DocumentSaveException>()),
    );
  });
}
