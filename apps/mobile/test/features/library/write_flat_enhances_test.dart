import 'dart:io';
import 'dart:typed_data';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/library/document_file_store.dart';
import 'package:mobile/features/library/drift/app_database.dart';
import 'package:mobile/features/library/drift/drift_document_repository.dart';
import 'package:mobile/features/library/hybrid_warper.dart';
import 'package:mobile/features/library/jpeg_exif_scrubber.dart';
import 'package:mobile/features/library/pdf/pdf_builder.dart';

void main() {
  test('editing a page with a grayscale mode regenerates a gray flat, base '
      'stays colored', () async {
    final base = await Directory.systemTemp.createTemp('wfenh');
    final db = AppDatabase(NativeDatabase.memory());
    final store = DocumentFileStore(base);
    final repo = DriftDocumentRepository(
      db: db,
      scrubber: const JpegExifScrubber(),
      fileStore: store,
      clock: DateTime.now,
      pdfBuilder: const PdfBuilder(),
      warper: const HybridWarper(),
    );

    // Solid red 40x40 base.
    final red = img.Image(width: 40, height: 40);
    img.fill(red, color: img.ColorRgb8(220, 20, 20));
    final baseBytes = Uint8List.fromList(img.encodeJpg(red, quality: 95));
    final now = DateTime.now();
    final id = await db.into(db.documents).insert(
          DocumentsCompanion.insert(name: 'D', createdAt: now, modifiedAt: now),
        );
    final rel = 'documents/$id/page_1.jpg';
    await store.writeRelative(rel, baseBytes);
    await db.into(db.pages).insert(
          PagesCompanion.insert(
            documentId: id,
            position: 1,
            relativeImagePath: rel,
            enhancerMode: const Value(1), // grayscale
          ),
        );

    // Re-apply a (bent) crop so a flat is generated with grayscale mode.
    const crop = CropCorners(
      topLeft: Offset(0.1, 0.1),
      topRight: Offset(0.9, 0.12),
      bottomRight: Offset(0.88, 0.9),
      bottomLeft: Offset(0.12, 0.88),
    );
    await repo.updatePageCorners(id, 1, crop);

    final pages = await repo.getDocumentPages(id);
    final flatPath = pages.single.flatImagePath;
    expect(flatPath, isNotNull);

    // Flat is grayscale: sampled center pixel has R≈G≈B.
    final flat = img.decodeImage(File(flatPath!).readAsBytesSync())!;
    final p = flat.getPixel(flat.width ~/ 2, flat.height ~/ 2);
    expect((p.r - p.g).abs(), lessThan(6));
    expect((p.g - p.b).abs(), lessThan(6));

    // Base is untouched (still red).
    final storedBase =
        img.decodeImage(File('${base.path}/$rel').readAsBytesSync())!;
    final bp = storedBase.getPixel(20, 20);
    expect(bp.r, greaterThan(bp.b + 40)); // clearly red, not gray

    await db.close();
    await base.delete(recursive: true);
  });
}
