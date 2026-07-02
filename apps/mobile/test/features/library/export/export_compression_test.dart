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

Future<(DriftDocumentRepository, AppDatabase, Directory, int)> _seed() async {
  final base = await Directory.systemTemp.createTemp('q1cmp');
  final db = AppDatabase(NativeDatabase.memory());
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
  final id = await db.into(db.documents).insert(
      DocumentsCompanion.insert(name: 'Doc', createdAt: now, modifiedAt: now));
  final image = img.Image(width: 3000, height: 2000);
  for (var y = 0; y < 2000; y++) {
    for (var x = 0; x < 3000; x++) {
      image.setPixelRgb(x, y, x % 256, y % 256, (x + y) % 256);
    }
  }
  final jpeg = Uint8List.fromList(img.encodeJpg(image, quality: 95));
  const rel = 'documents/1/page_1.jpg';
  await store.writeRelative(rel, jpeg);
  await db.into(db.pages).insert(
      PagesCompanion.insert(documentId: id, position: 1, relativeImagePath: rel));
  return (repo, db, base, id);
}

void main() {
  test('exportPdf at low is smaller than at original', () async {
    final (repo, db, base, id) = await _seed();
    final original = await (await repo.exportPdf(id)).readAsBytes();
    final low =
        await (await repo.exportPdf(id, quality: ExportQuality.low)).readAsBytes();
    expect(low.length, lessThan(original.length));
    await db.close();
    await base.delete(recursive: true);
  });

  test('exportPageAsImage at low is smaller than at original', () async {
    final (repo, db, base, id) = await _seed();
    final original = await (await repo.exportPageAsImage(id, 1)).readAsBytes();
    final low = await (await repo.exportPageAsImage(id, 1,
            quality: ExportQuality.low))
        .readAsBytes();
    expect(low.length, lessThan(original.length));
    await db.close();
    await base.delete(recursive: true);
  });
}
