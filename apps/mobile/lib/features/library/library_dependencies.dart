import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/logging/app_logger.dart';
import 'dart_page_processor.dart';
import 'document_file_store.dart';
import 'document_printer.dart';
import 'document_repository.dart';
import 'drift/app_database.dart';
import 'drift/drift_document_repository.dart';
import 'fallback_page_processor.dart';
import 'hybrid_warper.dart';
import 'native_page_processor.dart';
import 'jpeg_exif_scrubber.dart';
import 'ocr/mlkit_ocr_engine.dart';
import 'pdf/ocr_pdf_text_layer.dart';
import 'pdf/pdf_builder.dart';
import 'fax_provider.dart';
import 'feature_flags.dart';
import 'file_archiver.dart';
import 'link_share_channel.dart';
import 'share_channel.dart';

typedef DocumentRepositoryFactory = Future<DocumentRepository> Function();

/// Composition root for the Library feature (parallel to ScanDependencies).
/// Production builds a Drift-backed repository; tests inject a fake factory.
class LibraryDependencies {
  final DocumentRepositoryFactory createRepository;
  final DocumentPrinter printer;
  final ShareChannel share;
  final FileArchiver archiver;
  final LinkShareChannel linkShare;
  final FaxProvider fax;
  final FeatureFlags features;
  final AppLogger Function() logger;
  const LibraryDependencies({
    this.createRepository = _defaultCreateRepository,
    this.printer = const SystemDocumentPrinter(),
    this.share = const SystemShareChannel(),
    this.archiver = const SystemFileArchiver(),
    this.linkShare = const UnavailableLinkShareChannel(),
    this.fax = const UnavailableFaxProvider(),
    this.features = const FeatureFlags(),
    this.logger = _defaultLogger,
  });
}

AppLogger _defaultLogger() => const PrintAppLogger();

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
    pdfBuilder: const PdfBuilder(
      textLayer: OcrPdfTextLayer(),
      ocrFontLoader: loadOcrPdfFont,
    ),
    warper: const HybridWarper(),
    pageProcessor: const FallbackPageProcessor(
      primary: NativePageProcessor(),
      fallback: DartPageProcessor(HybridWarper()),
    ),
    ocrEngine: const MlKitOcrEngine(),
  );
}
