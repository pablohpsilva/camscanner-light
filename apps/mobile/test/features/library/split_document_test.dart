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
import 'package:mobile/features/library/enhancer_mode.dart';
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
    base = await Directory.systemTemp.createTemp('m1split');
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

  Uint8List jpeg() => Uint8List.fromList(
    img.encodeJpg(img.Image(width: 8, height: 8), quality: 90),
  );

  // Creates a document with [pageCount] pages; the LAST page optionally gets a
  // flat + OCR so we can prove they are carried across a split.
  Future<int> seedDoc(int pageCount, {bool lastHasFlatOcr = false}) async {
    final now = DateTime.now();
    final id = await db
        .into(db.documents)
        .insert(
          DocumentsCompanion.insert(
            name: 'Doc',
            createdAt: now,
            modifiedAt: now,
          ),
        );
    for (var pos = 1; pos <= pageCount; pos++) {
      final rel = 'documents/$id/page_$pos.jpg';
      await store.writeRelative(rel, jpeg());
      String? flatRel;
      String? ocrText;
      String? ocrBoxes;
      if (pos == pageCount && lastHasFlatOcr) {
        flatRel = store.flatForImage(rel);
        await store.writeRelative(flatRel, jpeg());
        ocrText = 'TAIL';
        ocrBoxes = const OcrResult(
          text: 'TAIL',
          words: [
            OcrWordBox(
              text: 'TAIL',
              left: 0.1,
              top: 0.1,
              right: 0.2,
              bottom: 0.2,
            ),
          ],
        ).encodeBoxes();
      }
      await db
          .into(db.pages)
          .insert(
            PagesCompanion.insert(
              documentId: id,
              position: pos,
              relativeImagePath: rel,
              flatRelativePath: Value(flatRel),
              ocrText: Value(ocrText),
              ocrBoxes: Value(ocrBoxes),
            ),
          );
    }
    return id;
  }

  test(
    'moves trailing pages into a new document; source keeps the head',
    () async {
      final id = await seedDoc(3, lastHasFlatOcr: true);
      final created = await repo.splitAfter(id, 1);

      // Source keeps only page 1.
      final srcPages = await repo.getDocumentPages(id);
      expect(srcPages.length, 1);
      expect(srcPages.single.position, 1);

      // New document has the former pages 2 and 3, renumbered 1 and 2.
      expect(created.name, endsWith('(split)'));
      final newPages = await repo.getDocumentPages(created.id);
      expect(newPages.length, 2);
      expect(newPages.map((p) => p.position), [1, 2]);
      for (final p in newPages) {
        expect(File(p.imagePath).existsSync(), isTrue);
      }
      // The former last page (now position 2) kept its flat + OCR.
      final tail = newPages[1];
      expect(tail.flatImagePath, isNotNull);
      expect(File(tail.flatImagePath!).existsSync(), isTrue);
      expect(tail.ocrText, 'TAIL');
      expect(tail.ocrWords, isNotEmpty);
    },
  );

  test('splitting after the last page throws', () async {
    final id = await seedDoc(2);
    await expectLater(
      repo.splitAfter(id, 2),
      throwsA(isA<DocumentSaveException>()),
    );
  });

  test('splitting after position 0 throws', () async {
    final id = await seedDoc(2);
    await expectLater(
      repo.splitAfter(id, 0),
      throwsA(isA<DocumentSaveException>()),
    );
  });

  test(
    'preserves enhancerMode and rotationQuarterTurns on the moved page',
    () async {
      final id = await seedDoc(2);

      // Give the page that will be moved (position 2) a non-default filter
      // + rotation, as if the user had applied a grayscale filter and
      // rotated it once before splitting.
      final movingPage =
          await (db.select(db.pages)
                ..where((t) => t.documentId.equals(id))
                ..where((t) => t.position.equals(2)))
              .getSingle();
      await (db.update(
        db.pages,
      )..where((t) => t.id.equals(movingPage.id))).write(
        const PagesCompanion(
          enhancerMode: Value(1), // EnhancerMode.grayscale
          rotationQuarterTurns: Value(1),
        ),
      );

      final created = await repo.splitAfter(id, 1);

      final newPages = await repo.getDocumentPages(created.id);
      expect(newPages.length, 1);
      final moved = newPages.single;
      expect(moved.enhancerMode, EnhancerMode.grayscale);
      expect(moved.rotationQuarterTurns, 1);
    },
  );
}
