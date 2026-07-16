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
      final doc = await _docRow(documentId); // ONE doc fetch (PERF-02b)
      final bytes = await _pdfBuilder.build(
        pages,
        quality: quality,
        idCardLayout: doc?.isIdCard ?? false,
      );
      final dir = await Directory.systemTemp.createTemp('pdf_export');
      final file = File('${dir.path}/${_sanitizeName(doc?.name)}.pdf');
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
      final doc = await _docRow(documentId); // ONE doc fetch (PERF-02b)
      final bytes = await _pdfBuilder.build(
        pages,
        idCardLayout: doc?.isIdCard ?? false,
      );
      final encrypted = await _encryptor.encrypt(bytes, password);
      final dir = await Directory.systemTemp.createTemp('pdf_protect');
      final file = File('${dir.path}/${_sanitizeName(doc?.name)}.pdf');
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
    // Display image: the flattened derivative when present, else the original.
    final srcRel = row.flatRelativePath ?? row.relativeImagePath;
    final base = await _exportBaseName(documentId);
    return _writePageImageFile(
      _fileStore.absoluteFor(srcRel).path,
      base,
      position,
      quality,
    );
  }

  Future<List<File>> exportAllPagesAsImages(
    int documentId, {
    ExportQuality quality = ExportQuality.original,
  }) async {
    final pages = await _pageDao.getDocumentPages(documentId);
    if (pages.isEmpty) {
      throw const DocumentExportException('exportAll failed: no pages');
    }
    // Reuse the already-loaded pages + one base-name fetch — no per-page row
    // re-select (PERF-02a).
    final base = await _exportBaseName(documentId);
    final files = <File>[];
    for (final page in pages) {
      files.add(
        await _writePageImageFile(
          page.displayPath,
          base,
          page.position,
          quality,
        ),
      );
    }
    return files;
  }

  /// Compresses + scrubs the display image at [displayAbsPath] and writes it to
  /// a temp `<base>_page_<position>.jpg`. Shared by the single- and all-pages
  /// image exports so a page row is selected at most once (PERF-02a).
  ///
  /// Privacy: writes to the OS temp/cache dir, NOT the persistent document store
  /// (which is backed up to Google/iCloud) — temp is self-purging and
  /// backup-excluded, same discipline as the PDF/text exports.
  Future<File> _writePageImageFile(
    String displayAbsPath,
    String baseName,
    int position,
    ExportQuality quality,
  ) async {
    try {
      final bytes = await File(displayAbsPath).readAsBytes();
      final compressed = await _compressor.compress(bytes, quality);
      final scrubbed = _scrubber.scrub(compressed); // privacy: always scrub
      final dir = await Directory.systemTemp.createTemp('img_export');
      final file = File('${dir.path}/${baseName}_page_$position.jpg');
      await file.writeAsBytes(scrubbed, flush: true);
      return file;
    } catch (e) {
      if (e is DocumentExportException) rethrow;
      throw DocumentExportException('exportImage failed: $e');
    }
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

  /// The documents row for [documentId], fetched ONCE per export so callers
  /// thread `name`/`isIdCard` instead of re-querying per helper (PERF-02b).
  Future<Document?> _docRow(int documentId) => (_db.select(
    _db.documents,
  )..where((d) => d.id.equals(documentId))).getSingleOrNull();

  /// Sanitized base name (no extension) from an already-fetched document [name];
  /// 'document' when empty/unknown. Pure — shared by every filename builder.
  String _sanitizeName(String? name) {
    final base = (name ?? 'document')
        .replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '_')
        .trim();
    return base.isEmpty ? 'document' : base;
  }

  /// Sanitized base name for [documentId] — one doc fetch (PERF-02b). Used by
  /// the image/text exports, which need only the name.
  Future<String> _exportBaseName(int documentId) async =>
      _sanitizeName((await _docRow(documentId))?.name);
}
