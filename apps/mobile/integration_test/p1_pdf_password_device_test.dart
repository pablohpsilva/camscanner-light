import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:mobile/features/library/document_file_store.dart';
import 'package:mobile/features/library/drift/app_database.dart';
import 'package:mobile/features/library/drift/drift_document_repository.dart';
import 'package:mobile/features/library/hybrid_warper.dart';
import 'package:mobile/features/library/jpeg_exif_scrubber.dart';
import 'package:mobile/features/library/pdf/pdf_builder.dart';

String _ascii(List<int> b) {
  final s = StringBuffer();
  for (final c in b) {
    s.writeCharCode(c);
  }
  return s.toString();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('exportProtectedPdf produces an encrypted PDF on device',
      (tester) async {
    final base = await Directory.systemTemp.createTemp('p1dev');
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

    final now = DateTime.now();
    final id = await db.into(db.documents).insert(DocumentsCompanion.insert(
        name: 'Doc', createdAt: now, modifiedAt: now));
    final rel = 'documents/$id/page_1.jpg';
    await store.writeRelative(rel,
        Uint8List.fromList(img.encodeJpg(img.Image(width: 8, height: 8), quality: 90)));
    await db.into(db.pages).insert(PagesCompanion.insert(
        documentId: id, position: 1, relativeImagePath: rel));

    final file = await repo.exportProtectedPdf(id, 'secret');
    final bytes = await file.readAsBytes();
    expect(_ascii(bytes.sublist(0, 4)), '%PDF');
    expect(_ascii(bytes).contains('/Encrypt'), isTrue);

    await db.close();
    await base.delete(recursive: true);
  });
}
