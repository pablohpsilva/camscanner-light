import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'document_file_store.dart';
import 'document_printer.dart';
import 'document_repository.dart';
import 'drift/app_database.dart';
import 'drift/drift_document_repository.dart';
import 'hybrid_warper.dart';
import 'jpeg_exif_scrubber.dart';
import 'ocr/mlkit_ocr_engine.dart';
import 'pdf/ocr_pdf_text_layer.dart';
import 'pdf/pdf_builder.dart';
import 'share_channel.dart';

typedef DocumentRepositoryFactory = Future<DocumentRepository> Function();

/// Composition root for the Library feature (parallel to ScanDependencies).
/// Production builds a Drift-backed repository; tests inject a fake factory.
class LibraryDependencies {
  final DocumentRepositoryFactory createRepository;
  final DocumentPrinter printer;
  final ShareChannel share;
  const LibraryDependencies({
    this.createRepository = _defaultCreateRepository,
    this.printer = const SystemDocumentPrinter(),
    this.share = const SystemShareChannel(),
  });
}

Future<DocumentRepository> _defaultCreateRepository() async {
  final docsDir = await getApplicationDocumentsDirectory();
  final supportDir = await getApplicationSupportDirectory();
  final dbFile = File(p.join(supportDir.path, 'camscanner.sqlite'));
  final db = AppDatabase(openAppDatabase(dbFile));
  return DriftDocumentRepository(
    db: db,
    scrubber: const JpegExifScrubber(),
    fileStore: DocumentFileStore(docsDir),
    clock: DateTime.now,
    pdfBuilder: const PdfBuilder(textLayer: OcrPdfTextLayer()),
    warper: const HybridWarper(),
    ocrEngine: const MlKitOcrEngine(),
  );
}
