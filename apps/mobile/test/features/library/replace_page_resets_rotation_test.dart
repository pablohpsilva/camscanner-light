import 'dart:io';
import 'dart:typed_data';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile/features/library/document_file_store.dart';
import 'package:mobile/features/library/drift/app_database.dart';
import 'package:mobile/features/library/drift/drift_document_repository.dart';
import 'package:mobile/features/library/hybrid_warper.dart';
import 'package:mobile/features/library/jpeg_exif_scrubber.dart';
import 'package:mobile/features/library/pdf/pdf_builder.dart';
import 'package:mobile/features/scan/captured_image.dart';

void main() {
  test('replacePage resets rotationQuarterTurns to 0', () async {
    final base = await Directory.systemTemp.createTemp('retake');
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
    addTearDown(() async {
      await db.close();
      if (await base.exists()) await base.delete(recursive: true);
    });
    final now = DateTime.now();
    final id = await db
        .into(db.documents)
        .insert(
          DocumentsCompanion.insert(name: 'D', createdAt: now, modifiedAt: now),
        );
    final rel = 'documents/$id/page_1.jpg';
    await store.writeRelative(
      rel,
      Uint8List.fromList(img.encodeJpg(img.Image(width: 40, height: 20))),
    );
    await db
        .into(db.pages)
        .insert(
          PagesCompanion.insert(
            documentId: id,
            position: 1,
            relativeImagePath: rel,
            rotationQuarterTurns: const Value(3),
          ),
        );
    // A fresh capture image on disk.
    final capPath = '${base.path}/cap.jpg';
    File(
      capPath,
    ).writeAsBytesSync(img.encodeJpg(img.Image(width: 40, height: 20)));

    await repo.replacePage(id, 1, CapturedImage(capPath));

    final page = await (db.select(
      db.pages,
    )..where((t) => t.documentId.equals(id))).getSingle();
    expect(page.rotationQuarterTurns, 0);
  });
}
