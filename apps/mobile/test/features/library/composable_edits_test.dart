import 'dart:io';
import 'dart:typed_data';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/library/document_file_store.dart';
import 'package:mobile/features/library/document_repository.dart';
import 'package:mobile/features/library/drift/app_database.dart';
import 'package:mobile/features/library/drift/drift_document_repository.dart';
import 'package:mobile/features/library/hybrid_warper.dart';
import 'package:mobile/features/library/jpeg_exif_scrubber.dart';
import 'package:mobile/features/library/pdf/pdf_builder.dart';

void main() {
  late AppDatabase db;
  late DriftDocumentRepository repo;
  late DocumentFileStore store;
  late Directory base;
  late String baseRel;

  setUp(() async {
    base = await Directory.systemTemp.createTemp('compose');
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

  Future<int> seed() async {
    final now = DateTime.now();
    final id = await db
        .into(db.documents)
        .insert(
          DocumentsCompanion.insert(name: 'D', createdAt: now, modifiedAt: now),
        );
    baseRel = 'documents/$id/page_1.jpg';
    // 60x40 landscape so rotation (dims swap) is observable.
    await store.writeRelative(
      baseRel,
      Uint8List.fromList(img.encodeJpg(img.Image(width: 60, height: 40))),
    );
    await db
        .into(db.pages)
        .insert(
          PagesCompanion.insert(
            documentId: id,
            position: 1,
            relativeImagePath: baseRel,
          ),
        );
    return id;
  }

  const crop = CropCorners(
    topLeft: Offset(0.1, 0.1),
    topRight: Offset(0.9, 0.1),
    bottomRight: Offset(0.9, 0.9),
    bottomLeft: Offset(0.1, 0.9),
  );

  Future<img.Image> display(int id) async {
    final p = (await repo.getDocumentPages(id)).single;
    // displayPath falls back to the base image when flatImagePath is null —
    // which is the correct, intentional state after 4 rotations return to
    // the identity (display == base, so _writeFlat clears the flat).
    return img.decodeImage(File(p.displayPath).readAsBytesSync())!;
  }

  Uint8List baseBytes() => store.absoluteFor(baseRel).readAsBytesSync();

  test('rotate once -> portrait 40x60', () async {
    final id = await seed();
    await repo.rotatePage(id, 1);
    final d = await display(id);
    expect([d.width, d.height], [40, 60]);
  });

  test('rotate twice -> 60x40; four times -> identity dims', () async {
    final id = await seed();
    await repo.rotatePage(id, 1);
    await repo.rotatePage(id, 1);
    expect([(await display(id)).width, (await display(id)).height], [60, 40]);
    await repo.rotatePage(id, 1);
    await repo.rotatePage(id, 1);
    expect([(await display(id)).width, (await display(id)).height], [60, 40]);
  });

  test(
    'rotate THEN crop keeps the rotation (portrait stays portrait)',
    () async {
      final id = await seed();
      await repo.rotatePage(id, 1); // 60x40 -> 40x60
      await repo.updatePageCorners(id, 1, crop);
      final d = await display(id);
      expect(
        d.height,
        greaterThan(d.width),
        reason: 'rotation must survive a later crop',
      );
    },
  );

  test('crop THEN rotate swaps the cropped dims', () async {
    final id = await seed();
    await repo.updatePageCorners(id, 1, crop);
    final afterCrop = await display(id);
    await repo.rotatePage(id, 1);
    final afterRot = await display(id);
    expect(afterRot.width, afterCrop.height);
    expect(afterRot.height, afterCrop.width);
  });

  test(
    'crop -> rotate -> crop -> rotate does not throw and stays cropped',
    () async {
      final id = await seed();
      await repo.updatePageCorners(id, 1, crop);
      await repo.rotatePage(id, 1);
      await repo.updatePageCorners(id, 1, crop);
      await repo.rotatePage(id, 1);
      final p = (await repo.getDocumentPages(id)).single;
      expect(p.flatImagePath, isNotNull);
    },
  );

  test('reset crop to fullFrame while rotated keeps rotation', () async {
    final id = await seed();
    await repo.rotatePage(id, 1); // portrait 40x60
    await repo.updatePageCorners(id, 1, crop);
    await repo.updatePageCorners(id, 1, CropCorners.fullFrame); // clear crop
    final d = await display(id);
    expect(
      [d.width, d.height],
      [40, 60],
      reason: 'clearing crop returns the rotated full frame, not the base',
    );
  });

  test('base bytes are never modified by crop or rotate', () async {
    final id = await seed();
    final before = baseBytes();
    await repo.rotatePage(id, 1);
    await repo.updatePageCorners(id, 1, crop);
    await repo.rotatePage(id, 1);
    expect(baseBytes(), before);
  });

  test('rotatePage throws for a missing page', () async {
    await seed();
    expect(
      () => repo.rotatePage(999, 1),
      throwsA(isA<DocumentSaveException>()),
    );
  });
}
