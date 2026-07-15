import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:mobile/features/library/document_file_store.dart';
import 'package:mobile/features/library/drift/app_database.dart';
import 'package:mobile/features/library/drift/drift_document_repository.dart';
import 'package:mobile/features/library/hybrid_warper.dart';
import 'package:mobile/features/library/jpeg_exif_scrubber.dart';
import 'package:mobile/features/library/ocr/mlkit_ocr_engine.dart';
import 'package:mobile/features/library/pdf/pdf_builder.dart';
import 'package:mobile/features/library/recognized_text_screen.dart';
import 'package:mobile/l10n/l10n.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('recognized text renders in-app and exports as .txt on device', (
    tester,
  ) async {
    final base = await Directory.systemTemp.createTemp('o4dev');
    final db = AppDatabase(NativeDatabase.memory());
    final store = DocumentFileStore(base);
    final repo = DriftDocumentRepository(
      db: db,
      scrubber: const JpegExifScrubber(),
      fileStore: store,
      clock: DateTime.now,
      pdfBuilder: const PdfBuilder(),
      warper: const HybridWarper(),
      ocrEngine: const MlKitOcrEngine(),
    );

    // Seed a page with a real "scanned" JPEG (black text on white).
    final now = DateTime.now();
    final docId = await db
        .into(db.documents)
        .insert(
          DocumentsCompanion.insert(
            name: 'Doc',
            createdAt: now,
            modifiedAt: now,
          ),
        );
    final rel = 'documents/$docId/page_1.jpg';
    final image = img.Image(width: 720, height: 220);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    img.drawString(
      image,
      'HELLO WORLD',
      font: img.arial48,
      x: 40,
      y: 80,
      color: img.ColorRgb8(0, 0, 0),
    );
    await store.writeRelative(
      rel,
      Uint8List.fromList(img.encodeJpg(image, quality: 95)),
    );
    await db
        .into(db.pages)
        .insert(
          PagesCompanion.insert(
            documentId: docId,
            position: 1,
            relativeImagePath: rel,
          ),
        );

    await repo.runOcr(docId, 1);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RecognizedTextScreen(
          documentId: docId,
          position: 1,
          name: 'Doc',
          repository: repo,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('recognized-text-body')), findsOneWidget);
    expect(find.textContaining('HELLO'), findsWidgets);

    final file = await repo.exportRecognizedText(docId, 1);
    expect((await file.readAsString()).toUpperCase(), contains('HELLO'));

    await db.close();
    await base.delete(recursive: true);
  });
}
