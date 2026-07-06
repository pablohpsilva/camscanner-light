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
import 'package:mobile/features/library/export/export_quality.dart';
import 'package:mobile/features/library/hybrid_warper.dart';
import 'package:mobile/features/library/jpeg_exif_scrubber.dart';
import 'package:mobile/features/library/page_image.dart';
import 'package:mobile/features/library/pdf/pdf_builder.dart';

/// Records the page list handed to the PDF builder so tests can assert the
/// combined export's page count and order without parsing a PDF.
class RecordingPdfBuilder extends PdfBuilder {
  final List<List<PageImage>> calls = <List<PageImage>>[];
  RecordingPdfBuilder();

  @override
  Future<Uint8List> build(List<PageImage> pages,
      {bool compress = true,
      ExportQuality quality = ExportQuality.original}) async {
    calls.add(List<PageImage>.of(pages));
    return Uint8List.fromList(const [0x25, 0x50, 0x44, 0x46, 0x0A]); // "%PDF\n"
  }
}

void main() {
  late AppDatabase db;
  late DriftDocumentRepository repo;
  late DocumentFileStore store;
  late Directory base;
  late RecordingPdfBuilder pdf;

  setUp(() async {
    base = await Directory.systemTemp.createTemp('combined');
    db = AppDatabase(NativeDatabase.memory());
    store = DocumentFileStore(base);
    pdf = RecordingPdfBuilder();
    repo = DriftDocumentRepository(
      db: db,
      scrubber: const JpegExifScrubber(),
      fileStore: store,
      clock: DateTime.now,
      pdfBuilder: pdf,
      warper: const HybridWarper(),
    );
  });

  tearDown(() async {
    await db.close();
    if (await base.exists()) await base.delete(recursive: true);
  });

  Uint8List jpeg() =>
      Uint8List.fromList(img.encodeJpg(img.Image(width: 8, height: 8), quality: 90));

  Future<int> seedDoc(String name, int pageCount) async {
    final now = DateTime.now();
    final id = await db.into(db.documents).insert(
        DocumentsCompanion.insert(name: name, createdAt: now, modifiedAt: now));
    for (var pos = 1; pos <= pageCount; pos++) {
      final rel = 'documents/$id/page_$pos.jpg';
      await store.writeRelative(rel, jpeg());
      await db.into(db.pages).insert(PagesCompanion.insert(
          documentId: id,
          position: pos,
          relativeImagePath: rel,
          flatRelativePath: const Value(null)));
    }
    return id;
  }

  test('concatenates all pages across documents in list then position order',
      () async {
    final a = await seedDoc('A', 2);
    final b = await seedDoc('B', 3);

    final file = await repo.exportCombinedPdf([a, b]);

    expect(file.path, endsWith('.pdf'));
    expect(file.path.startsWith(Directory.systemTemp.path), isTrue);
    expect(await file.exists(), isTrue);

    final built = pdf.calls.single;
    expect(built.length, 5);
    expect(built.map((p) => p.imagePath), [
      '${base.path}/documents/$a/page_1.jpg',
      '${base.path}/documents/$a/page_2.jpg',
      '${base.path}/documents/$b/page_1.jpg',
      '${base.path}/documents/$b/page_2.jpg',
      '${base.path}/documents/$b/page_3.jpg',
    ]);
  });

  test('throws on an empty document list', () async {
    expect(() => repo.exportCombinedPdf(const []),
        throwsA(isA<DocumentExportException>()));
  });

  test('throws when no selected document has any page', () async {
    final empty = await db.into(db.documents).insert(DocumentsCompanion.insert(
        name: 'Empty', createdAt: DateTime.now(), modifiedAt: DateTime.now()));
    expect(() => repo.exportCombinedPdf([empty]),
        throwsA(isA<DocumentExportException>()));
  });
}
