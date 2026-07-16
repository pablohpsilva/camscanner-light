import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document_file_store.dart';
import 'package:mobile/features/library/drift/app_database.dart';
import 'package:mobile/features/library/drift/drift_document_repository.dart';
import 'package:mobile/features/library/enhancer_mode.dart';
import 'package:mobile/features/library/jpeg_exif_scrubber.dart';
import 'package:mobile/features/library/pdf/pdf_builder.dart';

import '../../support/fake_library.dart';

/// P10 T10.4: `_cloneSourcePage` must carry EVERY page column across a merge /
/// split — a dropped column silently corrupts the copied page. Guards against a
/// future column being added to the insert in one path but not the shared helper.
void main() {
  late Directory base;
  late AppDatabase db;

  setUp(() {
    base = Directory.systemTemp.createTempSync('clone');
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() async {
    await db.close();
    if (base.existsSync()) base.deleteSync(recursive: true);
  });

  DriftDocumentRepository repo() => DriftDocumentRepository(
    db: db,
    scrubber: const JpegExifScrubber(),
    fileStore: DocumentFileStore(base),
    clock: () => DateTime.utc(2026, 1, 1),
    pdfBuilder: const PdfBuilder(),
    warper: FakeImageWarper(),
  );

  Future<int> seedDoc(String name) => db
      .into(db.documents)
      .insert(
        DocumentsCompanion.insert(
          name: name,
          createdAt: DateTime.utc(2026, 1, 1),
          modifiedAt: DateTime.utc(2026, 1, 1),
        ),
      );

  Future<void> seedPage(
    int docId,
    int pos, {
    String? ocrText,
    int rotation = 0,
    int enhancerMode = 0,
    bool withFlat = false,
  }) async {
    final rel = 'documents/$docId/page_$pos.jpg';
    File('${base.path}/$rel')
      ..createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3]);
    String? flatRel;
    if (withFlat) {
      flatRel = 'documents/$docId/page_${pos}_flat.jpg';
      File('${base.path}/$flatRel').writeAsBytesSync([4, 5, 6]);
    }
    await db
        .into(db.pages)
        .insert(
          PagesCompanion.insert(
            documentId: docId,
            position: pos,
            relativeImagePath: rel,
            ocrText: Value(ocrText),
            rotationQuarterTurns: Value(rotation),
            enhancerMode: Value(enhancerMode),
            flatRelativePath: Value(flatRel),
          ),
        );
  }

  test(
    'mergeInto carries ocrText, rotation, enhancerMode and the flat',
    () async {
      final target = await seedDoc('target');
      await seedPage(target, 1);
      final source = await seedDoc('source');
      await seedPage(
        source,
        1,
        ocrText: 'HELLO WORLD',
        rotation: 2,
        enhancerMode: EnhancerMode.color.index,
        withFlat: true,
      );

      await repo().mergeInto(target, source);

      final pages = await repo().getDocumentPages(target);
      expect(pages, hasLength(2));
      final merged = pages.firstWhere((p) => p.position == 2);
      expect(merged.ocrText, 'HELLO WORLD', reason: 'ocrText dropped');
      expect(merged.rotationQuarterTurns, 2, reason: 'rotation dropped');
      expect(
        merged.enhancerMode,
        EnhancerMode.color,
        reason: 'enhancerMode dropped',
      );
      expect(
        merged.flatImagePath,
        isNotNull,
        reason: 'flat derivative dropped',
      );
    },
  );

  test(
    'splitAfter carries ocrText, rotation, enhancerMode and the flat',
    () async {
      final docId = await seedDoc('splitme');
      await seedPage(docId, 1);
      await seedPage(
        docId,
        2,
        ocrText: 'PAGE TWO TEXT',
        rotation: 3,
        enhancerMode: EnhancerMode.grayscale.index,
        withFlat: true,
      );

      final newDoc = await repo().splitAfter(docId, 1); // moves page 2

      final pages = await repo().getDocumentPages(newDoc.id);
      expect(pages, hasLength(1));
      final moved = pages.single;
      expect(moved.ocrText, 'PAGE TWO TEXT', reason: 'ocrText dropped');
      expect(moved.rotationQuarterTurns, 3, reason: 'rotation dropped');
      expect(
        moved.enhancerMode,
        EnhancerMode.grayscale,
        reason: 'enhancerMode dropped',
      );
      expect(moved.flatImagePath, isNotNull, reason: 'flat derivative dropped');
    },
  );
}
