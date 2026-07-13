import 'dart:io';
import 'dart:typed_data';
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
import 'package:mobile/features/library/pdf/pdf_builder.dart';

void main() {
  late AppDatabase db;
  late DocumentFileStore store;
  late DriftDocumentRepository repo;
  late Directory base;
  late int id;
  late String rel;
  late Uint8List baseBytes;

  setUp(() async {
    base = await Directory.systemTemp.createTemp('upenh');
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
    final red = img.Image(width: 40, height: 40);
    img.fill(red, color: img.ColorRgb8(220, 20, 20));
    baseBytes = Uint8List.fromList(img.encodeJpg(red, quality: 95));
    final now = DateTime.now();
    id = await db.into(db.documents).insert(
          DocumentsCompanion.insert(name: 'D', createdAt: now, modifiedAt: now),
        );
    rel = 'documents/$id/page_1.jpg';
    await store.writeRelative(rel, baseBytes);
    await db.into(db.pages).insert(
          PagesCompanion.insert(
            documentId: id,
            position: 1,
            relativeImagePath: rel,
          ),
        );
  });

  tearDown(() async {
    await db.close();
    if (await base.exists()) await base.delete(recursive: true);
  });

  test('applies a grayscale filter: flat is gray, base is pristine, mode '
      'persisted', () async {
    await repo.updatePageEnhancer(id, 1, EnhancerMode.grayscale);

    final pages = await repo.getDocumentPages(id);
    expect(pages.single.enhancerMode, EnhancerMode.grayscale);
    final flatPath = pages.single.flatImagePath;
    expect(flatPath, isNotNull);
    final flat = img.decodeImage(File(flatPath!).readAsBytesSync())!;
    final p = flat.getPixel(20, 20);
    expect((p.r - p.g).abs(), lessThan(6));
    expect((p.g - p.b).abs(), lessThan(6));

    // Base byte-identical.
    expect(File('${base.path}/$rel').readAsBytesSync(), baseBytes);
  });

  test('no stacking: grayscale then Original yields an un-enhanced display',
      () async {
    await repo.updatePageEnhancer(id, 1, EnhancerMode.grayscale);
    await repo.updatePageEnhancer(id, 1, EnhancerMode.none);

    final pages = await repo.getDocumentPages(id);
    expect(pages.single.enhancerMode, EnhancerMode.none);
    // Full-frame + none → display equals the (colored) base, no flat.
    expect(pages.single.flatImagePath, isNull);
    expect(pages.single.displayPath, pages.single.imagePath);
  });

  test('throws when the page does not exist', () async {
    expect(
      () => repo.updatePageEnhancer(id, 99, EnhancerMode.auto),
      throwsA(isA<DocumentSaveException>()),
    );
  });
}
