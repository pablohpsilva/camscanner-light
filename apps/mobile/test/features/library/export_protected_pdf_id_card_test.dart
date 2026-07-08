import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile/features/library/document_file_store.dart';
import 'package:mobile/features/library/drift/app_database.dart';
import 'package:mobile/features/library/drift/drift_document_repository.dart';
import 'package:mobile/features/library/export/export_quality.dart';
import 'package:mobile/features/library/hybrid_warper.dart';
import 'package:mobile/features/library/jpeg_exif_scrubber.dart';
import 'package:mobile/features/library/page_image.dart';
import 'package:mobile/features/library/pdf/pdf_builder.dart';
import 'package:mobile/features/library/pdf/pdf_encryptor.dart';

/// Captures every [build] call and the [idCardLayout] flag passed to it.
/// Returns a minimal valid-enough byte sequence so the encryptor/writer don't
/// blow up.
class _RecordingPdfBuilder extends PdfBuilder {
  final List<({List<PageImage> pages, bool idCardLayout})> calls = [];

  @override
  Future<Uint8List> build(List<PageImage> pages,
      {bool compress = true,
      ExportQuality quality = ExportQuality.original,
      bool idCardLayout = false}) async {
    calls.add((pages: List<PageImage>.of(pages), idCardLayout: idCardLayout));
    // Return a minimal %PDF header so downstream code won't fail on an empty buf.
    return Uint8List.fromList(const [0x25, 0x50, 0x44, 0x46, 0x0A]); // %PDF\n
  }
}

/// Passthrough encryptor: returns the bytes unchanged so the file write works.
class _PassthroughEncryptor implements PdfEncryptor {
  const _PassthroughEncryptor();

  @override
  Future<Uint8List> encrypt(Uint8List pdfBytes, String password) async =>
      pdfBytes;
}

void main() {
  late AppDatabase db;
  late DriftDocumentRepository repo;
  late DocumentFileStore store;
  late Directory base;
  late _RecordingPdfBuilder pdf;

  setUp(() async {
    base = await Directory.systemTemp.createTemp('prot_id_card');
    db = AppDatabase(NativeDatabase.memory());
    store = DocumentFileStore(base);
    pdf = _RecordingPdfBuilder();
    repo = DriftDocumentRepository(
      db: db,
      scrubber: const JpegExifScrubber(),
      fileStore: store,
      clock: DateTime.now,
      pdfBuilder: pdf,
      warper: const HybridWarper(),
      encryptor: const _PassthroughEncryptor(),
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
          documentId: id, position: pos, relativeImagePath: rel));
    }
    return id;
  }

  test(
      'exportProtectedPdf calls build with idCardLayout=true for an ID-card document',
      () async {
    final id = await seedDoc('My ID', 2);
    await repo.markAsIdCard(id);

    await repo.exportProtectedPdf(id, 'secret');

    expect(pdf.calls, hasLength(1));
    expect(pdf.calls.single.idCardLayout, isTrue,
        reason:
            'build() must be called with idCardLayout=true for an ID-card document');
  });

  test(
      'exportProtectedPdf calls build with idCardLayout=false for a non-ID-card document',
      () async {
    final id = await seedDoc('Regular doc', 2);
    // Deliberately NOT calling markAsIdCard.

    await repo.exportProtectedPdf(id, 'secret');

    expect(pdf.calls, hasLength(1));
    expect(pdf.calls.single.idCardLayout, isFalse,
        reason:
            'build() must be called with idCardLayout=false for a non-ID-card document');
  });
}
