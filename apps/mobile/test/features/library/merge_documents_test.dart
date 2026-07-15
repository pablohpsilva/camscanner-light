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
    base = await Directory.systemTemp.createTemp('l1merge');
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

  // Creates a document with [pageCount] pages; page 1 optionally gets a flat + boxes.
  Future<int> seedDoc(
    String name,
    int pageCount, {
    bool firstHasFlat = false,
    String? firstOcrText,
  }) async {
    final now = DateTime.now();
    final id = await db
        .into(db.documents)
        .insert(
          DocumentsCompanion.insert(
            name: name,
            createdAt: now,
            modifiedAt: now,
          ),
        );
    for (var pos = 1; pos <= pageCount; pos++) {
      final rel = 'documents/$id/page_$pos.jpg';
      await store.writeRelative(rel, jpeg());
      String? flatRel;
      if (pos == 1 && firstHasFlat) {
        flatRel = store.flatForImage(rel);
        await store.writeRelative(flatRel, jpeg());
      }
      await db
          .into(db.pages)
          .insert(
            PagesCompanion.insert(
              documentId: id,
              position: pos,
              relativeImagePath: rel,
              flatRelativePath: Value(flatRel),
              ocrText: Value(pos == 1 ? firstOcrText : null),
              ocrBoxes: Value(
                pos == 1 && firstOcrText != null
                    ? const OcrResult(
                        text: 'x',
                        words: [
                          OcrWordBox(
                            text: 'x',
                            left: 0.1,
                            top: 0.1,
                            right: 0.2,
                            bottom: 0.2,
                          ),
                        ],
                      ).encodeBoxes()
                    : null,
              ),
            ),
          );
    }
    return id;
  }

  test(
    'appends source pages to target in order and deletes the source',
    () async {
      final target = await seedDoc('Target', 2);
      final source = await seedDoc(
        'Source',
        2,
        firstHasFlat: true,
        firstOcrText: 'HELLO',
      );

      await repo.mergeInto(target, source);

      final pages = await repo.getDocumentPages(target);
      expect(pages.length, 4);
      expect(pages.map((p) => p.position), [1, 2, 3, 4]);
      // The merged first source page (now position 3) kept its flat + OCR.
      final merged = pages[2];
      expect(merged.flatImagePath, isNotNull);
      expect(File(merged.flatImagePath!).existsSync(), isTrue);
      expect(merged.ocrText, 'HELLO');
      expect(merged.ocrWords, isNotEmpty);
      expect(File(merged.imagePath).existsSync(), isTrue);
      expect(merged.imagePath, contains('page_m${source}_1.jpg'));

      // Source is gone (rows + dir).
      expect(await repo.getDocumentPages(source), isEmpty);
      expect(Directory('${base.path}/documents/$source').existsSync(), isFalse);
    },
  );

  test(
    'merging a source page without a flat leaves flatImagePath null',
    () async {
      final target = await seedDoc('T', 1);
      final source = await seedDoc('S', 1); // no flat
      await repo.mergeInto(target, source);
      final pages = await repo.getDocumentPages(target);
      expect(pages.length, 2);
      expect(pages[1].flatImagePath, isNull);
    },
  );

  test('rejects merging a document into itself', () async {
    final id = await seedDoc('Self', 1);
    expect(() => repo.mergeInto(id, id), throwsA(isA<DocumentSaveException>()));
  });

  test(
    'preserves enhancerMode and rotationQuarterTurns on the copied page',
    () async {
      final target = await seedDoc('Target', 1);
      final source = await seedDoc('Source', 1);

      // Give the source's page a non-default filter + rotation, as if the
      // user had applied a grayscale filter and rotated it once before merging.
      final sourcePage = await (db.select(
        db.pages,
      )..where((t) => t.documentId.equals(source))).getSingle();
      await (db.update(
        db.pages,
      )..where((t) => t.id.equals(sourcePage.id))).write(
        const PagesCompanion(
          enhancerMode: Value(1), // EnhancerMode.grayscale
          rotationQuarterTurns: Value(1),
        ),
      );

      await repo.mergeInto(target, source);

      final pages = await repo.getDocumentPages(target);
      expect(pages.length, 2);
      final merged = pages[1];
      expect(merged.enhancerMode, EnhancerMode.grayscale);
      expect(merged.rotationQuarterTurns, 1);
    },
  );
}
