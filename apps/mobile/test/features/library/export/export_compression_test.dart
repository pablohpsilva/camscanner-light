import 'dart:io';
import 'dart:typed_data';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile/features/library/document_file_store.dart';
import 'package:mobile/features/library/drift/app_database.dart';
import 'package:mobile/features/library/drift/drift_document_repository.dart';
import 'package:mobile/features/library/export/export_quality.dart';
import 'package:mobile/features/library/jpeg_exif_scrubber.dart';
import 'package:mobile/features/library/pdf/pdf_builder.dart';
import 'package:mobile/features/library/perspective_warper.dart';

/// Seeds an in-memory repo with [pages] large (3000x2000) JPEG pages so the
/// compressor has real room to shrink. Cleanup is registered via addTearDown,
/// so the temp dir + db are released even if an assertion throws. Page files
/// are named from the actual document id (no hardcoded id assumption).
Future<(DriftDocumentRepository, int)> _seed({int pages = 1}) async {
  final base = await Directory.systemTemp.createTemp('q1cmp');
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(() async {
    await db.close();
    await base.delete(recursive: true);
  });
  final store = DocumentFileStore(base);
  final repo = DriftDocumentRepository(
    db: db,
    scrubber: const JpegExifScrubber(),
    fileStore: store,
    clock: DateTime.now,
    pdfBuilder: const PdfBuilder(),
    warper: const PerspectiveWarper(),
  );
  final now = DateTime.now();
  final id = await db
      .into(db.documents)
      .insert(
        DocumentsCompanion.insert(name: 'Doc', createdAt: now, modifiedAt: now),
      );
  final image = img.Image(width: 3000, height: 2000);
  for (var y = 0; y < 2000; y++) {
    for (var x = 0; x < 3000; x++) {
      image.setPixelRgb(x, y, x % 256, y % 256, (x + y) % 256);
    }
  }
  final jpeg = Uint8List.fromList(img.encodeJpg(image, quality: 95));
  for (var pos = 1; pos <= pages; pos++) {
    final rel = 'documents/$id/page_$pos.jpg';
    await store.writeRelative(rel, jpeg);
    await db
        .into(db.pages)
        .insert(
          PagesCompanion.insert(
            documentId: id,
            position: pos,
            relativeImagePath: rel,
          ),
        );
  }
  return (repo, id);
}

void main() {
  test('exportPdf at low is smaller than at original', () async {
    final (repo, id) = await _seed();
    final original = await (await repo.exportPdf(id)).readAsBytes();
    final low = await (await repo.exportPdf(
      id,
      quality: ExportQuality.low,
    )).readAsBytes();
    expect(low.length, lessThan(original.length));
  });

  test('exportPageAsImage at low is smaller than at original', () async {
    final (repo, id) = await _seed();
    final original = await (await repo.exportPageAsImage(id, 1)).readAsBytes();
    final low = await (await repo.exportPageAsImage(
      id,
      1,
      quality: ExportQuality.low,
    )).readAsBytes();
    expect(low.length, lessThan(original.length));
  });

  test('exportAllPagesAsImages threads quality to every page', () async {
    final (repo, id) = await _seed(pages: 2);
    // Read the original-quality bytes BEFORE the low-quality call overwrites
    // the per-page export files (both calls write to the same export paths).
    final originalFiles = await repo.exportAllPagesAsImages(id);
    final originalSizes = [
      for (final f in originalFiles) (await f.readAsBytes()).length,
    ];
    final lowFiles = await repo.exportAllPagesAsImages(
      id,
      quality: ExportQuality.low,
    );
    final lowSizes = [for (final f in lowFiles) (await f.readAsBytes()).length];

    expect(lowFiles.length, 2);
    for (var i = 0; i < 2; i++) {
      expect(
        lowSizes[i],
        lessThan(originalSizes[i]),
        reason: 'page ${i + 1} should be smaller at low quality',
      );
    }
  });
}
