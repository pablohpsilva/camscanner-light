import 'dart:io';

import '../document_file_store.dart';
import '../document_repository.dart';
import '../drift/app_database.dart';
import '../drift/page_dao.dart';
import '../image_metadata_scrubber.dart';
import '../page_image.dart';
import '../pdf/pdf_builder.dart';
import '../pdf/pdf_encryptor.dart';
import 'export_quality.dart';
import 'image_compressor.dart';

/// Owns every document export format (P05 T05.4 / GOD-01): PDF, combined,
/// separate, protected, page-image, all-images, and recognized text — plus the
/// filename builders and the ID-card layout flag. HOLDS the concrete
/// PDF-encryption + image-compression implementations (default-constructed
/// here, NOT in the persistence layer — SOLID-02), so the repository no longer
/// imports them. Reads pages via [PageDao]; document metadata via the DB.
class DocumentExporter {
  final AppDatabase _db;
  final DocumentFileStore _fileStore;
  final PageDao _pageDao;
  final PdfBuilder _pdfBuilder;
  final ImageMetadataScrubber _scrubber;
  final PdfEncryptor _encryptor;
  final ImageCompressor _compressor;

  DocumentExporter({
    required AppDatabase db,
    required DocumentFileStore fileStore,
    required PdfBuilder pdfBuilder,
    required ImageMetadataScrubber scrubber,
    PageDao? pageDao,
    PdfEncryptor? encryptor,
    ImageCompressor? compressor,
  }) : _db = db, // ignore: prefer_initializing_formals
       _fileStore = fileStore, // ignore: prefer_initializing_formals
       _pdfBuilder = pdfBuilder, // ignore: prefer_initializing_formals
       _scrubber = scrubber, // ignore: prefer_initializing_formals
       _pageDao = pageDao ?? PageDao(db, fileStore),
       _encryptor = encryptor ?? const SyncfusionPdfEncryptor(),
       _compressor = compressor ?? const ImageLibraryCompressor();

  Future<File> exportPdf(
    int documentId, {
    ExportQuality quality = ExportQuality.original,
  }) async {
    final pages = await _pageDao.getDocumentPages(documentId);
    if (pages.isEmpty) {
      throw const DocumentExportException('export failed: no pages');
    }
    try {
      final bytes = await _pdfBuilder.build(
        pages,
        quality: quality,
        idCardLayout: await _isIdCard(documentId),
      );
      final dir = await Directory.systemTemp.createTemp('pdf_export');
      final safeName = await _pdfFileNameFor(documentId);
      final file = File('${dir.path}/$safeName');
      await file.writeAsBytes(bytes);
      return file;
    } catch (e) {
      if (e is DocumentExportException) rethrow; // uniform rethrow (P10 DUP-04)
      throw DocumentExportException('export failed: $e');
    }
  }

  Future<File> exportCombinedPdf(List<int> documentIds) async {
    if (documentIds.isEmpty) {
      throw const DocumentExportException(
        'combined export failed: no documents',
      );
    }
    final pages = <PageImage>[];
    for (final id in documentIds) {
      pages.addAll(await _pageDao.getDocumentPages(id));
    }
    if (pages.isEmpty) {
      throw const DocumentExportException('combined export failed: no pages');
    }
    try {
      final bytes = await _pdfBuilder.build(pages);
      final dir = await Directory.systemTemp.createTemp('pdf_combined');
      final file = File('${dir.path}/documents.pdf');
      await file.writeAsBytes(bytes);
      return file;
    } catch (e) {
      if (e is DocumentExportException) rethrow;
      throw DocumentExportException('combined export failed: $e');
    }
  }

  Future<List<File>> exportSeparatePdfs(List<int> documentIds) async {
    if (documentIds.isEmpty) {
      throw const DocumentExportException(
        'separate export failed: no documents',
      );
    }
    final files = <File>[];
    for (final id in documentIds) {
      files.add(await exportPdf(id));
    }
    return files;
  }

  Future<File> exportProtectedPdf(int documentId, String password) async {
    final pages = await _pageDao.getDocumentPages(documentId);
    if (pages.isEmpty) {
      throw const DocumentExportException('protect failed: no pages');
    }
    try {
      final bytes = await _pdfBuilder.build(
        pages,
        idCardLayout: await _isIdCard(documentId),
      );
      final encrypted = await _encryptor.encrypt(bytes, password);
      final dir = await Directory.systemTemp.createTemp('pdf_protect');
      final safeName = await _pdfFileNameFor(documentId);
      final file = File('${dir.path}/$safeName');
      await file.writeAsBytes(encrypted);
      return file;
    } catch (e) {
      if (e is DocumentExportException) rethrow;
      throw DocumentExportException('protect failed: $e');
    }
  }

  Future<File> exportPageAsImage(
    int documentId,
    int position, {
    ExportQuality quality = ExportQuality.original,
  }) async {
    final row = await _pageDao.requirePage(
      documentId,
      position,
      'exportImage failed',
      export: true,
    );
    try {
      // Display image: the flattened derivative when present, else the original.
      final srcRel = row.flatRelativePath ?? row.relativeImagePath;
      final bytes = await _fileStore.absoluteFor(srcRel).readAsBytes();
      final compressed = await _compressor.compress(bytes, quality);
      final scrubbed = _scrubber.scrub(compressed); // privacy: always scrub
      // Privacy: write to the OS temp/cache dir, NOT the persistent document
      // store. The store is included in Google/iCloud backups and would let
      // export derivatives accumulate there forever; temp is self-purging and
      // backup-excluded (same temp-file discipline as the PDF/text exports).
      final dir = await Directory.systemTemp.createTemp('img_export');
      final base = await _exportBaseName(documentId);
      final file = File('${dir.path}/${base}_page_$position.jpg');
      await file.writeAsBytes(scrubbed, flush: true);
      return file;
    } catch (e) {
      if (e is DocumentExportException) rethrow;
      throw DocumentExportException('exportImage failed: $e');
    }
  }

  Future<List<File>> exportAllPagesAsImages(
    int documentId, {
    ExportQuality quality = ExportQuality.original,
  }) async {
    final pages = await _pageDao.getDocumentPages(documentId);
    if (pages.isEmpty) {
      throw const DocumentExportException('exportAll failed: no pages');
    }
    final files = <File>[];
    for (final page in pages) {
      files.add(
        await exportPageAsImage(documentId, page.position, quality: quality),
      );
    }
    return files;
  }

  Future<File> exportRecognizedText(int documentId, int position) async {
    final row = await _pageDao.requirePage(
      documentId,
      position,
      'exportText failed',
      export: true,
    );
    final text = row.ocrText;
    if (text == null || text.trim().isEmpty) {
      throw const DocumentExportException(
        'exportText failed: no recognized text',
      );
    }
    try {
      final dir = await Directory.systemTemp.createTemp('txt_export');
      final base = await _exportBaseName(documentId);
      final file = File('${dir.path}/${base}_page_$position.txt');
      await file.writeAsString(text);
      return file;
    } catch (e) {
      if (e is DocumentExportException) rethrow; // uniform rethrow (P10 DUP-04)
      throw DocumentExportException('exportText failed: $e');
    }
  }

  Future<bool> _isIdCard(int documentId) async {
    final row = await (_db.select(
      _db.documents,
    )..where((d) => d.id.equals(documentId))).getSingleOrNull();
    return row?.isIdCard ?? false;
  }

  /// Sanitized base name (no extension) from the document's name; 'document'
  /// when the name is empty/unknown. Shared by all export filename builders.
  Future<String> _exportBaseName(int documentId) async {
    final doc = await (_db.select(
      _db.documents,
    )..where((d) => d.id.equals(documentId))).getSingleOrNull();
    final base = (doc?.name ?? 'document')
        .replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '_')
        .trim();
    return base.isEmpty ? 'document' : base;
  }

  Future<String> _pdfFileNameFor(int documentId) async =>
      '${await _exportBaseName(documentId)}.pdf';
}
