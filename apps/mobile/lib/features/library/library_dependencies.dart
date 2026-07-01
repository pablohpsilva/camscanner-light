import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'document_file_store.dart';
import 'document_repository.dart';
import 'drift/app_database.dart';
import 'drift/drift_document_repository.dart';
import 'hybrid_warper.dart';
import 'jpeg_exif_scrubber.dart';
import 'pdf/pdf_builder.dart';
import 'perspective_warper.dart';

typedef DocumentRepositoryFactory = Future<DocumentRepository> Function();

/// Composition root for the Library feature (parallel to ScanDependencies).
/// Production builds a Drift-backed repository; tests inject a fake factory.
class LibraryDependencies {
  final DocumentRepositoryFactory createRepository;
  const LibraryDependencies({this.createRepository = _defaultCreateRepository});
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
    pdfBuilder: const PdfBuilder(),
    warper: const HybridWarper(),
  );
}
