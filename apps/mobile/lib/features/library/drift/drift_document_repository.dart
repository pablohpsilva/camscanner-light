import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show compute, visibleForTesting;
import 'package:image/image.dart' as img;

import '../../../core/async/with_isolate_timeout.dart';

import '../../scan/captured_image.dart';
import '../crop_corners.dart';
import '../document.dart';
import '../document_file_store.dart';
import '../document_repository.dart';
import '../document_summary.dart';
import '../export/export_quality.dart';
import '../export/image_compressor.dart';
import '../dart_page_processor.dart';
import '../enhancer_mode.dart';
import '../ensure_jpeg.dart';
import '../image_enhancer.dart';
import '../image_metadata_scrubber.dart';
import '../image_warper.dart';
import '../page_processor.dart';
import '../warp_enhancer.dart';
import '../ocr/ocr_engine.dart';
import '../ocr/ocr_result.dart';
import '../page_image.dart';
import '../pdf/pdf_builder.dart';
import '../pdf/pdf_encryptor.dart';
import 'app_database.dart' hide Document;

/// Runs the rotate isolate call for a set of [RotateJpegArgs]. Injectable so a
/// test can substitute a never-completing runner to exercise the timeout guard;
/// production defaults to the real `compute(rotateAndBakeJpeg, ...)`.
typedef RotateRunner = Future<Uint8List?> Function(RotateJpegArgs args);

/// Drift-backed [DocumentRepository]. Scrubs the capture, writes the file, and
/// inserts the rows inside a single transaction so the DB never holds a partial
/// record. Stores RELATIVE image paths.
class DriftDocumentRepository implements DocumentRepository {
  final AppDatabase _db;
  final ImageMetadataScrubber _scrubber;
  final DocumentFileStore _fileStore;
  final DateTime Function() _clock;
  final PdfBuilder _pdfBuilder;
  final PageProcessor _processor;
  final OcrEngine _ocrEngine;
  final PdfEncryptor _encryptor;
  final ImageCompressor _compressor;

  /// Upper bound on the rotate decode+rotate+re-encode `compute()` isolate
  /// (CMP-10). A wedged isolate cannot be killed from Dart, so this only
  /// detaches the awaiting future; on expiry the rotate surfaces the same
  /// [DocumentSaveException] as an undecodable base. Injectable so tests can
  /// shrink it.
  final Duration rotateTimeout;

  /// Seam for the rotate isolate call (CMP-10). Defaults to the real
  /// `compute(rotateAndBakeJpeg, ...)`; tests inject a never-completing runner
  /// to drive the timeout path deterministically.
  final RotateRunner _rotateRunner;

  DriftDocumentRepository({
    required AppDatabase db,
    required ImageMetadataScrubber scrubber,
    required DocumentFileStore fileStore,
    required DateTime Function() clock,
    required PdfBuilder pdfBuilder,
    required ImageWarper warper,
    PageProcessor? pageProcessor,
    OcrEngine ocrEngine = const NoOpOcrEngine(),
    PdfEncryptor encryptor = const SyncfusionPdfEncryptor(),
    ImageCompressor compressor = const ImageLibraryCompressor(),
    this.rotateTimeout = const Duration(seconds: 12),
    @visibleForTesting RotateRunner? rotateRunner,
  }) : _rotateRunner =
           rotateRunner ?? ((args) => compute(rotateAndBakeJpeg, args)),
       _db = db, // ignore: prefer_initializing_formals
       _scrubber = scrubber, // ignore: prefer_initializing_formals
       _fileStore = fileStore, // ignore: prefer_initializing_formals
       _clock = clock, // ignore: prefer_initializing_formals
       _pdfBuilder = pdfBuilder, // ignore: prefer_initializing_formals
       _processor = pageProcessor ?? DartPageProcessor(warper),
       _ocrEngine = ocrEngine, // ignore: prefer_initializing_formals
       _encryptor = encryptor, // ignore: prefer_initializing_formals
       _compressor = compressor; // ignore: prefer_initializing_formals

  @override
  Future<Document> createFromCapture(
    CapturedImage capture, {
    CropCorners? corners,
    ImageEnhancer? enhancer,
  }) async {
    final now = _clock();
    final createdUtc = now.toUtc();
    final name = _defaultName(now);
    try {
      final doc = await _db.transaction(() async {
        final docId = await _db
            .into(_db.documents)
            .insert(
              DocumentsCompanion.insert(
                name: name,
                createdAt: createdUtc,
                modifiedAt: createdUtc,
              ),
            );
        final rel = _fileStore.relativeFor(docId, 1);
        late final Uint8List scrubbed;
        try {
          final raw = await File(capture.path).readAsBytes();
          scrubbed = _scrubber.scrub(ensureJpegBytes(Uint8List.fromList(raw)));
          // Base is PRISTINE and unfiltered — the filter is metadata, applied
          // when regenerating the flat. Never bake enhancement into the base.
          await _fileStore.writeRelative(rel, scrubbed);
        } catch (e) {
          await _fileStore.deleteDocumentDir(docId); // best-effort cleanup
          rethrow; // rolls back the inserted document row
        }
        final mode = enhancerModeOf(enhancer);
        final effective = corners ?? CropCorners.fullFrame;
        String? flatRel;
        try {
          flatRel = await _writeFlat(
            relativeImagePath: rel,
            quarterTurns: 0,
            corners: effective,
            mode: mode,
            existingFlatRel: null,
          );
        } catch (_) {
          flatRel = null; // IO/regen failure — save proceeds with base only
        }
        await _db
            .into(_db.pages)
            .insert(
              PagesCompanion.insert(
                documentId: docId,
                position: 1,
                relativeImagePath: rel,
                corners: Value(
                  effective == CropCorners.fullFrame
                      ? null
                      : effective.toStorage(),
                ),
                flatRelativePath: Value(flatRel),
                enhancerMode: Value(mode.index),
              ),
            );
        return Document(
          id: docId,
          name: name,
          createdAt: createdUtc,
          modifiedAt: createdUtc,
        );
      });
      await _deleteTempSource(capture.path);
      _triggerOcr(doc.id, 1);
      return doc;
    } catch (e) {
      throw DocumentSaveException('save failed: $e');
    }
  }

  @override
  Future<List<DocumentSummary>> listDocumentSummaries() => _summaries();

  // FTS5 operator characters stripped from every term before it reaches MATCH.
  static final RegExp _ftsOps = RegExp(r'''["*:^()\-]''');
  static const Set<String> _ftsKeywords = {'and', 'or', 'not', 'near'};

  // Raw query → safe search terms: operator chars removed, bareword boolean
  // keywords dropped, empties discarded. Never yields FTS syntax.
  List<String> _searchTerms(String q) => q
      .split(RegExp(r'\s+'))
      .map((t) => t.replaceAll(_ftsOps, ''))
      .where((t) => t.isNotEmpty && !_ftsKeywords.contains(t.toLowerCase()))
      .toList();

  @override
  Future<List<DocumentSummary>> searchDocuments(String query) async {
    final q = query.trim();
    if (q.isEmpty) return _summaries();
    final terms = _searchTerms(q);
    // Trigram MATCH needs every term >= 3 chars; anything shorter (or a query
    // that sanitizes to nothing) falls back to the unranked LIKE scan so short
    // words still match as substrings.
    if (terms.isEmpty || terms.any((t) => t.length < 3)) {
      return _searchByLike(q);
    }
    return _searchRanked(q, terms);
  }

  // Unranked substring search (pre-FTS O5 behavior): name OR any page ocr_text
  // LIKE %q%, newest-first. Retained for short-term / degenerate queries.
  Future<List<DocumentSummary>> _searchByLike(String q) async {
    final like = '%$q%';
    final idQuery =
        _db.select(_db.documents).join([
            leftOuterJoin(
              _db.pages,
              _db.pages.documentId.equalsExp(_db.documents.id),
            ),
          ])
          ..where(_db.documents.name.like(like) | _db.pages.ocrText.like(like))
          ..groupBy([_db.documents.id]);
    final ids = (await idQuery.get())
        .map((r) => r.readTable(_db.documents).id)
        .toSet();
    if (ids.isEmpty) return const [];
    return _summaries(onlyIds: ids);
  }

  // Ranked trigram search over per-document rows: bm25 relevance, with document
  // name matches ordered first. Returns summaries in relevance order.
  Future<List<DocumentSummary>> _searchRanked(
    String q,
    List<String> terms,
  ) async {
    final matchExpr = terms.map((t) => '"$t"').join(' AND ');
    final rows = await _db
        .customSelect(
          'SELECT rowid AS did, bm25(doc_fts) AS score '
          'FROM doc_fts WHERE doc_fts MATCH ? ORDER BY score',
          variables: [Variable.withString(matchExpr)],
        )
        .get();
    final textIds = rows.map((r) => r.read<int>('did')).toList(); // best first

    // Name matches: strong signal, and names are not in the trigram index.
    final nameRows =
        await (_db.select(_db.documents)
              ..where((t) => t.name.like('%$q%'))
              ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
            .get();

    final ordered = <int>[];
    final seen = <int>{};
    for (final d in nameRows) {
      if (seen.add(d.id)) ordered.add(d.id);
    }
    for (final id in textIds) {
      if (seen.add(id)) ordered.add(id);
    }
    if (ordered.isEmpty) return const [];

    final summaries = await _summaries(onlyIds: ordered.toSet());
    final rank = {for (var i = 0; i < ordered.length; i++) ordered[i]: i};
    summaries.sort(
      (a, b) => rank[a.document.id]!.compareTo(rank[b.document.id]!),
    );
    return summaries;
  }

  Future<List<DocumentSummary>> _summaries({Set<int>? onlyIds}) async {
    // (1) page count per document, newest doc first — one grouped query.
    final pageCount = _db.pages.id.count();
    final query =
        _db.select(_db.documents).join([
            leftOuterJoin(
              _db.pages,
              _db.pages.documentId.equalsExp(_db.documents.id),
            ),
          ])
          ..addColumns([pageCount])
          ..groupBy([_db.documents.id])
          ..orderBy([OrderingTerm.desc(_db.documents.createdAt)]);
    if (onlyIds != null) {
      query.where(_db.documents.id.isIn(onlyIds.toList()));
    }
    final rows = await query.get();

    // (2) lowest-position page path per document — one query, no N+1.
    final pages = await (_db.select(
      _db.pages,
    )..orderBy([(t) => OrderingTerm.asc(t.position)])).get();
    final firstPathByDoc = <int, String>{};
    for (final pg in pages) {
      firstPathByDoc.putIfAbsent(
        pg.documentId,
        () => pg.flatRelativePath ?? pg.relativeImagePath,
      );
    }

    return rows.map((row) {
      final d = row.readTable(_db.documents);
      final rel = firstPathByDoc[d.id];
      return DocumentSummary(
        document: Document(
          id: d.id,
          name: d.name,
          createdAt: d.createdAt,
          modifiedAt: d.modifiedAt,
        ),
        pageCount: row.read(pageCount)!,
        thumbnailPath: rel == null ? null : _fileStore.absoluteFor(rel).path,
      );
    }).toList();
  }

  @override
  Future<List<PageImage>> getDocumentPages(int documentId) async {
    final pages =
        await (_db.select(_db.pages)
              ..where((t) => t.documentId.equals(documentId))
              ..orderBy([(t) => OrderingTerm.asc(t.position)]))
            .get();
    return pages
        .map(
          (pg) => PageImage(
            position: pg.position,
            imagePath: _fileStore.absoluteFor(pg.relativeImagePath).path,
            corners: CropCorners.tryParse(pg.corners) ?? CropCorners.fullFrame,
            rotationQuarterTurns: pg.rotationQuarterTurns,
            enhancerMode:
                (pg.enhancerMode >= 0 &&
                        pg.enhancerMode < EnhancerMode.values.length)
                    ? EnhancerMode.values[pg.enhancerMode]
                    : EnhancerMode.none,
            flatImagePath: pg.flatRelativePath == null
                ? null
                : _fileStore.absoluteFor(pg.flatRelativePath!).path,
            ocrText: pg.ocrText,
            ocrWords: OcrResult.decodeBoxes(pg.ocrBoxes),
          ),
        )
        .toList();
  }

  // Intentionally does NOT bump documents.modifiedAt: OCR is a derived,
  // re-runnable cache, not user content, and a background run must not reorder
  // the library by recency. Each run OVERWRITES the page's cached OCR (so a
  // NoOp/failed pass clears it) — when O2 adds a real engine + auto-run, guard
  // the trigger so a no-text pass can't wipe previously recognized text.
  @override
  Future<void> runOcr(int documentId, int position) async {
    final row =
        await (_db.select(_db.pages)..where(
              (t) =>
                  t.documentId.equals(documentId) & t.position.equals(position),
            ))
            .getSingleOrNull();
    if (row == null) {
      throw DocumentSaveException('runOcr: no page ($documentId, $position)');
    }
    // Recognize the DISPLAY image (flat derivative if present, else original).
    final srcRel = row.flatRelativePath ?? row.relativeImagePath;
    final bytes = await _fileStore.absoluteFor(srcRel).readAsBytes();
    final result = await _ocrEngine.recognize(bytes);
    await (_db.update(_db.pages)..where((t) => t.id.equals(row.id))).write(
      PagesCompanion(
        ocrText: Value(result.text),
        ocrBoxes: Value(result.encodeBoxes()),
      ),
    );
  }

  @override
  Future<void> deleteDocument(int documentId) async {
    // Row-first: the DB delete is authoritative. Explicit page delete (not
    // relying solely on the FK cascade pragma), then the document row.
    await _db.transaction(() async {
      await (_db.delete(
        _db.pages,
      )..where((t) => t.documentId.equals(documentId))).go();
      await (_db.delete(
        _db.documents,
      )..where((t) => t.id.equals(documentId))).go();
    });
    // Best-effort file cleanup AFTER commit. Worst case = harmless orphan files
    // (no row references them). deleteDocumentDir guards dir-absent.
    await _fileStore.deleteDocumentDir(documentId);
  }

  @override
  Future<File> exportPdf(
    int documentId, {
    ExportQuality quality = ExportQuality.original,
  }) async {
    final pages = await getDocumentPages(documentId);
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
      throw DocumentExportException('export failed: $e');
    }
  }

  Future<bool> _isIdCard(int documentId) async {
    final row = await (_db.select(
      _db.documents,
    )..where((d) => d.id.equals(documentId))).getSingleOrNull();
    return row?.isIdCard ?? false;
  }

  @override
  Future<File> exportCombinedPdf(List<int> documentIds) async {
    if (documentIds.isEmpty) {
      throw const DocumentExportException(
        'combined export failed: no documents',
      );
    }
    final pages = <PageImage>[];
    for (final id in documentIds) {
      pages.addAll(await getDocumentPages(id));
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

  @override
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

  @override
  Future<File> exportProtectedPdf(int documentId, String password) async {
    final pages = await getDocumentPages(documentId);
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

  @override
  Future<File> exportPageAsImage(
    int documentId,
    int position, {
    ExportQuality quality = ExportQuality.original,
  }) async {
    final row =
        await (_db.select(_db.pages)..where(
              (t) =>
                  t.documentId.equals(documentId) & t.position.equals(position),
            ))
            .getSingleOrNull();
    if (row == null) {
      throw DocumentExportException(
        'exportImage failed: no page ($documentId, $position)',
      );
    }
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

  @override
  Future<List<File>> exportAllPagesAsImages(
    int documentId, {
    ExportQuality quality = ExportQuality.original,
  }) async {
    final pages = await getDocumentPages(documentId);
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

  @override
  Future<File> exportRecognizedText(int documentId, int position) async {
    final row =
        await (_db.select(_db.pages)..where(
              (t) =>
                  t.documentId.equals(documentId) & t.position.equals(position),
            ))
            .getSingleOrNull();
    if (row == null) {
      throw DocumentExportException(
        'exportText failed: no page ($documentId, $position)',
      );
    }
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
      throw DocumentExportException('exportText failed: $e');
    }
  }

  @override
  Future<Document> rename(int documentId, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) {
      throw const DocumentRenameException('rename failed: empty name');
    }
    final modifiedUtc = _clock().toUtc();
    final updated =
        await (_db.update(
          _db.documents,
        )..where((t) => t.id.equals(documentId))).write(
          DocumentsCompanion(
            name: Value(trimmed),
            modifiedAt: Value(modifiedUtc),
          ),
        );
    if (updated == 0) {
      throw const DocumentRenameException('rename failed: no such document');
    }
    final row = await (_db.select(
      _db.documents,
    )..where((t) => t.id.equals(documentId))).getSingle();
    return Document(
      id: row.id,
      name: row.name,
      createdAt: row.createdAt,
      modifiedAt: row.modifiedAt,
    );
  }

  /// Regenerates the display ("flat") derivative from the PRISTINE base by
  /// applying enhance ∘ rotate ∘ crop, and returns the new flat's relative path
  /// (or null when the display equals the base: no rotation, no crop, no
  /// filter). NEVER writes the base. [corners] are in the display frame
  /// (post-rotation).
  Future<String?> _writeFlat({
    required String relativeImagePath,
    required int quarterTurns,
    required CropCorners corners,
    required EnhancerMode mode,
    required String? existingFlatRel,
  }) async {
    final baseBytes = await _fileStore
        .absoluteFor(relativeImagePath)
        .readAsBytes();
    final isFullFrame = corners == CropCorners.fullFrame;

    // Fast path: the display equals the pristine base — no image work at all.
    if (quarterTurns == 0 && isFullFrame && mode == EnhancerMode.none) {
      await _deleteFlatIfPresent(existingFlatRel);
      return null;
    }

    // Rotation needs a full-res decode+rotate+re-encode — run it OFF the UI
    // isolate (`compute`). quarterTurns == 0 skips it (the processor bakes EXIF
    // orientation itself), so it consumes the base bytes directly.
    Uint8List? rotatedBytes;
    if (quarterTurns != 0) {
      // Guard the isolate (CMP-10): a wedged native/pure-Dart rotate cannot be
      // killed from Dart, so on expiry we detach and surface the SAME failure
      // contract as an undecodable base — callers already handle it (rotate
      // error UI). The success path is unchanged.
      rotatedBytes = await withIsolateTimeout(
        () => _rotateRunner(RotateJpegArgs(baseBytes, quarterTurns)),
        timeout: rotateTimeout,
        onTimeout: () => throw const DocumentSaveException(
          'regenerate: undecodable base image',
        ),
      );
      if (rotatedBytes == null) {
        throw const DocumentSaveException('regenerate: undecodable base image');
      }
    }
    final input = rotatedBytes ?? baseBytes;

    Uint8List? flatBytes;
    if (isFullFrame) {
      if (mode == EnhancerMode.none) {
        // quarterTurns != 0 here (pure pass-through handled above).
        flatBytes = rotatedBytes;
      } else {
        // Full-frame enhancement; fall back to the un-enhanced frame on failure
        // so a page is never lost.
        flatBytes =
            await _processor.process(input, CropCorners.fullFrame, mode) ??
            input;
      }
    } else {
      // Cropped: the processor warps + enhances in one pass (or two-step for a
      // stubbed warper). Fall back to the rotated-only image if it makes nothing.
      flatBytes = await _processor.process(input, corners, mode) ?? rotatedBytes;
    }

    if (flatBytes == null) {
      await _deleteFlatIfPresent(existingFlatRel);
      return null;
    }
    final flatRel =
        existingFlatRel ?? _fileStore.flatForImage(relativeImagePath);
    await _fileStore.writeRelative(flatRel, flatBytes);
    return flatRel;
  }

  Future<void> _deleteFlatIfPresent(String? rel) async {
    if (rel == null) return;
    try {
      await _fileStore.absoluteFor(rel).delete();
    } on FileSystemException {
      /* already gone — fine */
    }
  }

  static EnhancerMode _modeOf(int index) =>
      (index >= 0 && index < EnhancerMode.values.length)
      ? EnhancerMode.values[index]
      : EnhancerMode.none;

  @override
  Future<void> updatePageCorners(
    int documentId,
    int position,
    CropCorners corners,
  ) async {
    final page =
        await (_db.select(_db.pages)..where(
              (t) =>
                  t.documentId.equals(documentId) & t.position.equals(position),
            ))
            .getSingleOrNull();
    if (page == null) {
      throw DocumentSaveException(
        'updatePageCorners: no page ($documentId, $position)',
      );
    }
    // Corners arrive already in the DISPLAY frame (post-rotation) from the
    // editor; rotation is unchanged by a crop.
    final flatRel = await _writeFlat(
      relativeImagePath: page.relativeImagePath,
      quarterTurns: page.rotationQuarterTurns,
      corners: corners,
      mode: _modeOf(page.enhancerMode),
      existingFlatRel: page.flatRelativePath,
    );
    final isFullFrame = corners == CropCorners.fullFrame;
    await (_db.update(_db.pages)..where(
          (t) => t.documentId.equals(documentId) & t.position.equals(position),
        ))
        .write(
          PagesCompanion(
            corners: Value(isFullFrame ? null : corners.toStorage()),
            flatRelativePath: Value(flatRel),
          ),
        );
  }

  @override
  Future<void> rotatePage(int documentId, int position) async {
    final row =
        await (_db.select(_db.pages)..where(
              (t) =>
                  t.documentId.equals(documentId) & t.position.equals(position),
            ))
            .getSingleOrNull();
    if (row == null) {
      throw DocumentSaveException(
        'rotatePage: no page ($documentId, $position)',
      );
    }
    final turns = (row.rotationQuarterTurns + 1) % 4;
    // Keep the same physical crop in the newly-rotated display frame.
    final corners = (CropCorners.tryParse(row.corners) ?? CropCorners.fullFrame)
        .rotate90Cw();
    final isFullFrame = corners == CropCorners.fullFrame;
    final flatRel = await _writeFlat(
      relativeImagePath: row.relativeImagePath,
      quarterTurns: turns,
      corners: corners,
      mode: _modeOf(row.enhancerMode),
      existingFlatRel: row.flatRelativePath,
    );

    // Rotate cached OCR boxes CW to stay aligned; text is unchanged.
    final boxes = OcrResult.decodeBoxes(row.ocrBoxes);
    final String? newBoxes = boxes.isEmpty
        ? row.ocrBoxes
        : OcrResult(
            text: '',
            words: [for (final b in boxes) b.rotate90Cw()],
          ).encodeBoxes();

    await (_db.update(_db.pages)..where(
          (t) => t.documentId.equals(documentId) & t.position.equals(position),
        ))
        .write(
          PagesCompanion(
            rotationQuarterTurns: Value(turns),
            corners: Value(isFullFrame ? null : corners.toStorage()),
            flatRelativePath: Value(flatRel),
            ocrBoxes: Value(newBoxes),
          ),
        );
    await (_db.update(_db.documents)..where((d) => d.id.equals(documentId)))
        .write(DocumentsCompanion(modifiedAt: Value(_clock().toUtc())));
  }

  @override
  Future<void> updatePageEnhancer(
    int documentId,
    int position,
    EnhancerMode mode,
  ) async {
    final row =
        await (_db.select(_db.pages)..where(
              (t) =>
                  t.documentId.equals(documentId) & t.position.equals(position),
            ))
            .getSingleOrNull();
    if (row == null) {
      throw DocumentSaveException(
        'updatePageEnhancer: no page ($documentId, $position)',
      );
    }
    final corners =
        CropCorners.tryParse(row.corners) ?? CropCorners.fullFrame;
    final flatRel = await _writeFlat(
      relativeImagePath: row.relativeImagePath,
      quarterTurns: row.rotationQuarterTurns,
      corners: corners,
      mode: mode,
      existingFlatRel: row.flatRelativePath,
    );
    await (_db.update(_db.pages)..where((t) => t.id.equals(row.id))).write(
      PagesCompanion(
        enhancerMode: Value(mode.index),
        flatRelativePath: Value(flatRel),
      ),
    );
    await (_db.update(_db.documents)..where((d) => d.id.equals(documentId)))
        .write(DocumentsCompanion(modifiedAt: Value(_clock().toUtc())));
  }

  @override
  Future<int> addPageToDocument(
    int documentId,
    CapturedImage capture, {
    CropCorners? corners,
    ImageEnhancer? enhancer,
  }) async {
    try {
      final position = await _db.transaction(() async {
        final maxRow =
            await (_db.select(_db.pages)
                  ..where((p) => p.documentId.equals(documentId))
                  ..orderBy([(p) => OrderingTerm.desc(p.position)])
                  ..limit(1))
                .getSingleOrNull();
        if (maxRow == null) {
          throw DocumentSaveException('document $documentId has no pages');
        }
        final newPosition = maxRow.position + 1;
        final rel = _fileStore.relativeFor(documentId, newPosition);
        final raw = await File(capture.path).readAsBytes();
        final Uint8List scrubbed = _scrubber.scrub(ensureJpegBytes(raw));
        await _fileStore.writeRelative(rel, scrubbed); // pristine, unfiltered
        final mode = enhancerModeOf(enhancer);
        final effective = corners ?? CropCorners.fullFrame;
        String? flatRel;
        try {
          flatRel = await _writeFlat(
            relativeImagePath: rel,
            quarterTurns: 0,
            corners: effective,
            mode: mode,
            existingFlatRel: null,
          );
        } catch (_) {
          flatRel = null;
        }
        await _db
            .into(_db.pages)
            .insert(
              PagesCompanion.insert(
                documentId: documentId,
                position: newPosition,
                relativeImagePath: rel,
                corners: Value(
                  effective == CropCorners.fullFrame
                      ? null
                      : effective.toStorage(),
                ),
                flatRelativePath: Value(flatRel),
                enhancerMode: Value(mode.index),
              ),
            );
        await (_db.update(_db.documents)..where((d) => d.id.equals(documentId)))
            .write(DocumentsCompanion(modifiedAt: Value(_clock().toUtc())));
        return newPosition;
      });
      await _deleteTempSource(capture.path);
      _triggerOcr(documentId, position);
      return position;
    } catch (e) {
      if (e is DocumentSaveException) rethrow;
      throw DocumentSaveException('addPage failed: $e');
    }
  }

  @override
  Future<int> deletePage(int documentId, int position) async {
    final row =
        await (_db.select(_db.pages)..where(
              (t) =>
                  t.documentId.equals(documentId) & t.position.equals(position),
            ))
            .getSingleOrNull();
    if (row == null) {
      throw DocumentSaveException(
        'deletePage: no page ($documentId, $position)',
      );
    }
    final rows =
        await (_db.select(_db.pages)
              ..where((t) => t.documentId.equals(documentId))
              ..orderBy([(t) => OrderingTerm.asc(t.position)]))
            .get();
    final remaining = rows.length - 1;

    await _db.transaction(() async {
      await (_db.delete(_db.pages)..where((t) => t.id.equals(row.id))).go();
      if (remaining > 0) {
        // Renumber survivors whose position was above the deleted one: -1.
        for (final r in rows) {
          if (r.id == row.id) continue;
          if (r.position > position) {
            await (_db.update(_db.pages)..where((t) => t.id.equals(r.id)))
                .write(PagesCompanion(position: Value(r.position - 1)));
          }
        }
        await (_db.update(_db.documents)..where((d) => d.id.equals(documentId)))
            .write(DocumentsCompanion(modifiedAt: Value(_clock().toUtc())));
      } else {
        await (_db.delete(
          _db.documents,
        )..where((d) => d.id.equals(documentId))).go();
      }
    });

    // Best-effort file cleanup AFTER commit (DB is authoritative).
    if (remaining == 0) {
      await _fileStore.deleteDocumentDir(documentId);
    } else {
      try {
        await _fileStore.absoluteFor(row.relativeImagePath).delete();
      } on FileSystemException {
        /* already gone — fine */
      }
      final flat = row.flatRelativePath;
      if (flat != null) {
        try {
          await _fileStore.absoluteFor(flat).delete();
        } on FileSystemException {
          /* already gone — fine */
        }
      }
    }
    return remaining;
  }

  @override
  Future<void> replacePage(
    int documentId,
    int position,
    CapturedImage capture, {
    CropCorners? corners,
    ImageEnhancer? enhancer,
  }) async {
    try {
      final row =
          await (_db.select(_db.pages)..where(
                (t) =>
                    t.documentId.equals(documentId) &
                    t.position.equals(position),
              ))
              .getSingleOrNull();
      if (row == null) {
        throw DocumentSaveException(
          'replacePage: no page ($documentId, $position)',
        );
      }

      final raw = await File(capture.path).readAsBytes();
      final Uint8List scrubbed = _scrubber.scrub(ensureJpegBytes(raw));
      // Retake resets the chain; base is pristine and unfiltered.
      await _fileStore.writeRelative(row.relativeImagePath, scrubbed);

      // Retake = a fresh image: reset the transform chain to identity, then
      // regenerate the flat from the (new) base via the shared pipeline.
      final CropCorners effective = corners ?? CropCorners.fullFrame;
      final flatRel = await _writeFlat(
        relativeImagePath: row.relativeImagePath,
        quarterTurns: 0,
        corners: effective,
        mode: enhancerModeOf(enhancer),
        existingFlatRel: row.flatRelativePath,
      );

      await _db.transaction(() async {
        await (_db.update(_db.pages)..where((t) => t.id.equals(row.id))).write(
          PagesCompanion(
            rotationQuarterTurns: const Value(0),
            corners: Value(
              (corners == null || corners == CropCorners.fullFrame)
                  ? null
                  : corners.toStorage(),
            ),
            flatRelativePath: Value(flatRel),
            enhancerMode: Value(enhancerModeOf(enhancer).index),
          ),
        );
        await (_db.update(_db.documents)..where((d) => d.id.equals(documentId)))
            .write(DocumentsCompanion(modifiedAt: Value(_clock().toUtc())));
      });

      await _deleteTempSource(capture.path);
    } catch (e) {
      if (e is DocumentSaveException) rethrow;
      throw DocumentSaveException('replacePage failed: $e');
    }
  }

  @override
  Future<void> reorderPages(int documentId, List<int> orderedPositions) async {
    // Pre-fetch rows before the transaction to build a position→rowId map.
    // Updates inside the transaction use the primary key (id) to avoid
    // position-value conflicts when two pages swap positions.
    final rows =
        await (_db.select(_db.pages)
              ..where((t) => t.documentId.equals(documentId))
              ..orderBy([(t) => OrderingTerm.asc(t.position)]))
            .get();
    if (rows.isEmpty) {
      throw DocumentSaveException('reorderPages: no pages for $documentId');
    }
    final posToId = {for (final r in rows) r.position: r.id};

    await _db.transaction(() async {
      for (var i = 0; i < orderedPositions.length; i++) {
        final oldPosition = orderedPositions[i];
        final rowId = posToId[oldPosition];
        if (rowId == null) continue; // unknown position — skip
        final newPosition = i + 1;
        if (oldPosition == newPosition) continue; // no change needed
        await (_db.update(_db.pages)..where((t) => t.id.equals(rowId))).write(
          PagesCompanion(position: Value(newPosition)),
        );
      }
      await (_db.update(_db.documents)..where((d) => d.id.equals(documentId)))
          .write(DocumentsCompanion(modifiedAt: Value(_clock().toUtc())));
    });
  }

  @override
  Future<void> mergeInto(int targetDocumentId, int sourceDocumentId) async {
    if (targetDocumentId == sourceDocumentId) {
      throw const DocumentSaveException('mergeInto: target == source');
    }
    try {
      final maxRow =
          await (_db.select(_db.pages)
                ..where((p) => p.documentId.equals(targetDocumentId))
                ..orderBy([(p) => OrderingTerm.desc(p.position)])
                ..limit(1))
              .getSingleOrNull();
      final targetMax = maxRow?.position ?? 0;
      final sourcePages =
          await (_db.select(_db.pages)
                ..where((p) => p.documentId.equals(sourceDocumentId))
                ..orderBy([(p) => OrderingTerm.asc(p.position)]))
              .get();

      // Copy files first (outside the DB txn), building the row inserts.
      final inserts = <PagesCompanion>[];
      var k = 0;
      for (final src in sourcePages) {
        k++;
        final imageRel =
            'documents/$targetDocumentId/page_m${sourceDocumentId}_${src.position}.jpg';
        final srcBytes = await _fileStore
            .absoluteFor(src.relativeImagePath)
            .readAsBytes();
        await _fileStore.writeRelative(imageRel, srcBytes);
        String? flatRel;
        if (src.flatRelativePath != null) {
          final flatBytes = await _fileStore
              .absoluteFor(src.flatRelativePath!)
              .readAsBytes();
          flatRel = _fileStore.flatForImage(imageRel);
          await _fileStore.writeRelative(flatRel, flatBytes);
        }
        inserts.add(
          PagesCompanion.insert(
            documentId: targetDocumentId,
            position: targetMax + k,
            relativeImagePath: imageRel,
            corners: Value(src.corners),
            flatRelativePath: Value(flatRel),
            ocrText: Value(src.ocrText),
            ocrBoxes: Value(src.ocrBoxes),
            rotationQuarterTurns: Value(src.rotationQuarterTurns),
            enhancerMode: Value(src.enhancerMode),
          ),
        );
      }
      await _db.transaction(() async {
        for (final c in inserts) {
          await _db.into(_db.pages).insert(c);
        }
      });
      await (_db.update(_db.documents)
            ..where((d) => d.id.equals(targetDocumentId)))
          .write(DocumentsCompanion(modifiedAt: Value(_clock().toUtc())));
    } catch (e) {
      if (e is DocumentSaveException) rethrow;
      throw DocumentSaveException('mergeInto failed: $e');
    }
    // Remove the now-copied source (rows + dir). Separate from the txn above.
    await deleteDocument(sourceDocumentId);
  }

  @override
  Future<Document> splitAfter(int documentId, int position) async {
    try {
      final pages =
          await (_db.select(_db.pages)
                ..where((p) => p.documentId.equals(documentId))
                ..orderBy([(p) => OrderingTerm.asc(p.position)]))
              .get();
      if (pages.isEmpty) {
        throw DocumentSaveException('splitAfter: no pages ($documentId)');
      }
      final maxPos = pages.last.position;
      if (position < 1 || position >= maxPos) {
        throw DocumentSaveException(
          'splitAfter: nothing after position $position',
        );
      }
      final doc = await (_db.select(
        _db.documents,
      )..where((d) => d.id.equals(documentId))).getSingleOrNull();
      if (doc == null) {
        throw DocumentSaveException('splitAfter: no document $documentId');
      }
      final now = _clock().toUtc();
      final newName = '${doc.name} (split)';
      final newId = await _db
          .into(_db.documents)
          .insert(
            DocumentsCompanion.insert(
              name: newName,
              createdAt: now,
              modifiedAt: now,
            ),
          );

      final moved = pages.where((p) => p.position > position).toList();
      var k = 0;
      for (final src in moved) {
        k++;
        final imageRel = 'documents/$newId/page_$k.jpg';
        final bytes = await _fileStore
            .absoluteFor(src.relativeImagePath)
            .readAsBytes();
        await _fileStore.writeRelative(imageRel, bytes);
        String? flatRel;
        if (src.flatRelativePath != null) {
          final flatBytes = await _fileStore
              .absoluteFor(src.flatRelativePath!)
              .readAsBytes();
          flatRel = _fileStore.flatForImage(imageRel);
          await _fileStore.writeRelative(flatRel, flatBytes);
        }
        await _db
            .into(_db.pages)
            .insert(
              PagesCompanion.insert(
                documentId: newId,
                position: k,
                relativeImagePath: imageRel,
                corners: Value(src.corners),
                flatRelativePath: Value(flatRel),
                ocrText: Value(src.ocrText),
                ocrBoxes: Value(src.ocrBoxes),
                rotationQuarterTurns: Value(src.rotationQuarterTurns),
                enhancerMode: Value(src.enhancerMode),
              ),
            );
      }

      await _db.transaction(() async {
        for (final src in moved) {
          await (_db.delete(_db.pages)..where((t) => t.id.equals(src.id))).go();
        }
        await (_db.update(_db.documents)..where((d) => d.id.equals(documentId)))
            .write(DocumentsCompanion(modifiedAt: Value(now)));
      });

      // Best-effort cleanup of the moved pages' source files (after commit).
      for (final src in moved) {
        try {
          await _fileStore.absoluteFor(src.relativeImagePath).delete();
        } on FileSystemException {
          /* already gone */
        }
        final f = src.flatRelativePath;
        if (f != null) {
          try {
            await _fileStore.absoluteFor(f).delete();
          } on FileSystemException {
            /* already gone */
          }
        }
      }

      return Document(
        id: newId,
        name: newName,
        createdAt: now,
        modifiedAt: now,
      );
    } catch (e) {
      if (e is DocumentSaveException) rethrow;
      throw DocumentSaveException('splitAfter failed: $e');
    }
  }

  /// Fire-and-forget OCR after a save. Swallows errors — OCR must never fail a
  /// save — and does not run for the NoOp engine (skips wasted work in tests).
  void _triggerOcr(int documentId, int position) {
    if (_ocrEngine is NoOpOcrEngine) return;
    // ignore: discarded_futures
    runOcr(documentId, position).catchError((_) {});
  }

  String _defaultName(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return 'Scan ${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}.${two(t.minute)}.${two(t.second)}';
  }

  Future<void> _deleteTempSource(String path) async {
    try {
      final f = File(path);
      if (await f.exists() && path.contains(Directory.systemTemp.path)) {
        await f.delete();
      }
    } catch (_) {
      /* best-effort */
    }
  }

  @override
  Future<void> markAsIdCard(int documentId) async {
    final updated =
        await (_db.update(
          _db.documents,
        )..where((d) => d.id.equals(documentId))).write(
          DocumentsCompanion(
            isIdCard: const Value(true),
            modifiedAt: Value(_clock().toUtc()),
          ),
        );
    if (updated == 0) {
      throw const DocumentSaveException('markAsIdCard: document not found');
    }
  }
}

/// Arguments for [rotateAndBakeJpeg] — must be a top-level type so it can cross
/// the isolate boundary used by `compute`.
class RotateJpegArgs {
  final Uint8List bytes;
  final int quarterTurns;
  const RotateJpegArgs(this.bytes, this.quarterTurns);
}

/// Isolate entrypoint (top-level, for `compute`): decode [args.bytes], bake EXIF
/// orientation into the pixels (see _writeFlat's note — matches every other
/// pixel path), rotate 90°*quarterTurns clockwise, and re-encode as JPEG.
/// Returns null if the bytes can't be decoded. Full-res decode/rotate/encode is
/// CPU-heavy, so this runs off the UI isolate to keep edits from freezing it.
Uint8List? rotateAndBakeJpeg(RotateJpegArgs args) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(args.bytes);
  } catch (_) {
    decoded = null;
  }
  if (decoded == null) return null;
  final upright = img.bakeOrientation(decoded);
  final rotated = img.copyRotate(upright, angle: 90 * args.quarterTurns);
  return Uint8List.fromList(img.encodeJpg(rotated, quality: 95));
}
