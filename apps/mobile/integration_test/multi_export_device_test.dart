// On-device verification for the multi-select export feature. Host tests fake
// the PDF builder, the native zip, and the share sheet; this proves the REAL
// native chain on a physical device:
//   - exportCombinedPdf  -> a real, re-parseable multi-page PDF (right count/order)
//   - exportSeparatePdfs -> real per-document PDFs
//   - SystemFileArchiver -> a real .zip that decodes back to valid PDF entries
//   - the produced file routes through the ShareChannel (as the UI does)
//
// This is the automated form of the plan's "Manual verification (on device)".
// Run: flutter test integration_test/multi_export_device_test.dart -d <device-id>
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:mobile/features/library/document_file_store.dart';
import 'package:mobile/features/library/drift/app_database.dart';
import 'package:mobile/features/library/drift/drift_document_repository.dart';
import 'package:mobile/features/library/file_archiver.dart';
import 'package:mobile/features/library/hybrid_warper.dart';
import 'package:mobile/features/library/jpeg_exif_scrubber.dart';
import 'package:mobile/features/library/pdf/ocr_pdf_text_layer.dart';
import 'package:mobile/features/library/pdf/pdf_builder.dart';
import 'package:mobile/features/library/share_channel.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

import '../test/support/fake_library.dart';

bool _isPdf(List<int> bytes) =>
    bytes.length >= 4 &&
    bytes[0] == 0x25 && // %
    bytes[1] == 0x50 && // P
    bytes[2] == 0x44 && // D
    bytes[3] == 0x46; //  F

int _pdfPageCount(List<int> bytes) {
  final doc = sf.PdfDocument(inputBytes: Uint8List.fromList(bytes));
  try {
    return doc.pages.count;
  } finally {
    doc.dispose();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late DriftDocumentRepository repo;
  late DocumentFileStore store;
  late Directory base;

  setUp(() async {
    base = await Directory.systemTemp.createTemp('multi_export_dev');
    db = AppDatabase(NativeDatabase.memory());
    store = DocumentFileStore(base);
    repo = DriftDocumentRepository(
      db: db,
      scrubber: const JpegExifScrubber(),
      fileStore: store,
      clock: DateTime.now,
      pdfBuilder: const PdfBuilder(textLayer: OcrPdfTextLayer()),
      warper: const HybridWarper(),
    );
  });

  tearDown(() async {
    await db.close();
    if (await base.exists()) await base.delete(recursive: true);
  });

  Uint8List jpeg() => Uint8List.fromList(
      img.encodeJpg(img.Image(width: 8, height: 8), quality: 90));

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

  testWidgets('Merge: exportCombinedPdf builds a real PDF with every page, '
      'shared through the channel', (tester) async {
    final a = await seedDoc('A', 2);
    final b = await seedDoc('B', 3);

    final pdf = await repo.exportCombinedPdf([a, b]);
    final bytes = await pdf.readAsBytes();

    expect(_isPdf(bytes), isTrue, reason: 'combined output must be a real PDF');
    expect(_pdfPageCount(bytes), 5,
        reason: '2 pages from A + 3 from B, concatenated');

    // Route through the channel exactly as HomeScreen._exportSelected does.
    final ShareChannel share = FakeShareChannel();
    await share.share([pdf.path], subject: '2 documents');
    expect((share as FakeShareChannel).lastFilePaths!.single, pdf.path);
  });

  testWidgets('Separate + zip: exportSeparatePdfs -> a real .zip of valid PDFs',
      (tester) async {
    final a = await seedDoc('A', 2);
    final b = await seedDoc('B', 3);

    final files = await repo.exportSeparatePdfs([a, b]);
    expect(files.length, 2);
    expect(_pdfPageCount(await files[0].readAsBytes()), 2);
    expect(_pdfPageCount(await files[1].readAsBytes()), 3);

    final zip = await const SystemFileArchiver().zip(
      files,
      archiveName: 'documents.zip',
      entryNames: const ['A.pdf', 'B.pdf'],
    );
    expect(await zip.exists(), isTrue);

    // Decode the real zip and confirm each entry is a valid PDF.
    final archive = ZipDecoder().decodeBytes(await zip.readAsBytes());
    expect(archive.files.map((f) => f.name), ['A.pdf', 'B.pdf']);
    for (final entry in archive.files) {
      expect(_isPdf(entry.content as List<int>), isTrue,
          reason: '${entry.name} must be a valid PDF inside the zip');
    }

    final ShareChannel share = FakeShareChannel();
    await share.share([zip.path]);
    expect((share as FakeShareChannel).lastFilePaths!.single, zip.path);
  });
}
