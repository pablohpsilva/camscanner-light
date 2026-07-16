import 'dart:io';

import 'package:drift/drift.dart';

import '../../../core/logging/app_logger.dart';

import '../../scan/captured_image.dart';
import '../crop_corners.dart';
import '../document.dart' hide Page;
import '../document_file_store.dart';
import '../document_repository.dart';
import '../document_summary.dart';
import '../export/document_exporter.dart';
import '../export/export_quality.dart';
import '../dart_page_processor.dart';
import '../enhancer_mode.dart';
import '../ensure_jpeg.dart';
import '../image_enhancer.dart';
import '../image_metadata_scrubber.dart';
import '../image_warper.dart';
import '../jpeg_rotator.dart';
import '../page_derivative_pipeline.dart';
import '../page_ordering_service.dart';
import '../page_processor.dart';
import '../search/document_search_service.dart';
import '../warp_enhancer.dart';
import '../ocr/ocr_engine.dart';
import '../ocr/ocr_result.dart';
import '../ocr/ocr_service.dart';
import '../page_image.dart';
import '../pdf/pdf_builder.dart';
import 'app_database.dart' hide Document;
import 'page_dao.dart';

/// Drift-backed [DocumentRepository] — the ONLY persistence type the widget
/// layer sees. After P05 this is a thin COORDINATOR: it owns the capture-save /
/// page-edit write path (create/add/replace/crop/rotate/enhance) and trivial
/// document ops (rename/delete/markAsIdCard), and delegates the rest to focused
/// collaborators — [DocumentSearchService] (listing + FTS/LIKE search),
/// [DocumentExporter] (all export formats + the concrete PDF/compression
/// impls), [PageOrderingService] (reorder/delete/merge/split with their P03
/// atomicity), [PageDerivativePipeline] (flat regeneration), [PageDao] (page-row
/// queries), and [OcrService] (page OCR).
///
/// Its own write path keeps the P03 discipline: the capture is scrubbed and the
/// file written OUTSIDE any transaction (so the write lock is never held across
/// slow image work — SAFE-02), then the rows are inserted in a short
/// transaction. Stores RELATIVE image paths.
class DriftDocumentRepository implements DocumentRepository {
  final AppDatabase _db;
  final ImageMetadataScrubber _scrubber;
  final DocumentFileStore _fileStore;
  final DateTime Function() _clock;

  /// Owns every export format + the concrete PDF-encryption/compression impls
  /// (P05 T05.4 / SOLID-02), so the persistence layer no longer constructs or
  /// imports them. Built at the composition of this ctor (or injected).
  final DocumentExporter _exporter;

  /// Reports best-effort file-cleanup failures on a rolled-back merge/split
  /// (P03 SAFE-01). Const-defaulted so production wiring is silent-safe and
  /// tests can inject a recording [SilentAppLogger].
  final AppLogger _logger;

  /// Owns display-derivative ("flat") regeneration (P05 T05.5): enhance ∘
  /// rotate ∘ crop from the pristine base, holding the page processor and the
  /// injectable rotate isolate + its CMP-10 timeout.
  final PageDerivativePipeline _pipeline;

  /// Single home for page-row queries + row→PageImage mapping (P05 T05.3).
  final PageDao _pageDao;

  /// Library listing + FTS/LIKE search (P05 T05.6).
  final DocumentSearchService _search;

  /// Multi-row page ordering: reorder/delete/merge/split with their P03
  /// atomicity boundaries (P05 T05.6).
  final PageOrderingService _ordering;

  /// Page OCR + the fire-and-forget post-save trigger (P05 T05.7).
  final OcrService _ocr;

  DriftDocumentRepository({
    required AppDatabase db,
    required ImageMetadataScrubber scrubber,
    required DocumentFileStore fileStore,
    required DateTime Function() clock,
    required PdfBuilder pdfBuilder,
    required ImageWarper warper,
    PageProcessor? pageProcessor,
    OcrEngine ocrEngine = const NoOpOcrEngine(),
    Duration rotateTimeout = const Duration(seconds: 12),
    AppLogger logger = const PrintAppLogger(),
    JpegRotator rotator = const ComputeJpegRotator(),
    DocumentExporter? exporter,
  }) : _logger = logger, // ignore: prefer_initializing_formals
       _db = db, // ignore: prefer_initializing_formals
       _scrubber = scrubber, // ignore: prefer_initializing_formals
       _fileStore = fileStore, // ignore: prefer_initializing_formals
       _clock = clock, // ignore: prefer_initializing_formals
       _pipeline = PageDerivativePipeline(
         fileStore: fileStore,
         processor: pageProcessor ?? DartPageProcessor(warper),
         rotator: rotator,
         rotateTimeout: rotateTimeout,
       ),
       _pageDao = PageDao(db, fileStore),
       _search = DocumentSearchService(db, fileStore),
       _ordering = PageOrderingService(
         db,
         fileStore,
         PageDao(db, fileStore),
         clock,
         logger,
       ),
       _ocr = OcrService(
         db,
         fileStore,
         PageDao(db, fileStore),
         ocrEngine,
         logger,
       ),
       _exporter =
           exporter ??
           DocumentExporter(
             db: db,
             fileStore: fileStore,
             pdfBuilder: pdfBuilder,
             scrubber: scrubber,
           );

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
      // Reserve the document row first so we have a docId to name the page's
      // file — but do the slow read/scrub/flat work OUTSIDE any transaction
      // (P03 SAFE-02) so the write lock is not held across it. The narrow
      // window between this insert and the page insert can only leave a
      // harmless empty document on a hard crash (never a dangling page row);
      // a catchable base-write failure rolls the document row back below.
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
      final mode = enhancerModeOf(enhancer);
      final effective = corners ?? CropCorners.fullFrame;
      String? flatRel;
      try {
        final raw = await File(capture.path).readAsBytes();
        // Base is PRISTINE and unfiltered — the filter is metadata, applied
        // when regenerating the flat. Never bake enhancement into the base.
        final scrubbed = _scrubber.scrub(
          ensureJpegBytes(Uint8List.fromList(raw)),
        );
        await _fileStore.writeRelative(rel, scrubbed);
        try {
          flatRel = await _writeFlat(
            relativeImagePath: rel,
            quarterTurns: 0,
            corners: effective,
            mode: mode,
            existingFlatRel: null,
          );
        } catch (e, st) {
          flatRel = null; // IO/regen failure — save proceeds with base only
          _logger.error(
            e,
            stackTrace: st,
            context: 'createFromCapture: flat regen failed, saved base only',
          );
        }
      } catch (e) {
        // Base write failed: roll back the reserved document row + its dir so
        // no empty document is left behind.
        await (_db.delete(
          _db.documents,
        )..where((d) => d.id.equals(docId))).go();
        await _fileStore.deleteDocumentDir(docId);
        rethrow;
      }
      // Short transaction: insert only the page row.
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
      await _deleteTempSource(capture.path);
      _ocr.trigger(docId, 1);
      return Document(
        id: docId,
        name: name,
        createdAt: createdUtc,
        modifiedAt: createdUtc,
      );
    } catch (e) {
      throw DocumentSaveException('save failed: $e');
    }
  }

  @override
  Future<List<DocumentSummary>> listDocumentSummaries() =>
      _search.listSummaries();

  @override
  Future<List<DocumentSummary>> searchDocuments(String query) =>
      _search.search(query);

  @override
  Future<List<PageImage>> getDocumentPages(int documentId) =>
      _pageDao.getDocumentPages(documentId);

  @override
  Future<void> runOcr(int documentId, int position) =>
      _ocr.runOcr(documentId, position);

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
  }) => _exporter.exportPdf(documentId, quality: quality);

  @override
  Future<File> exportCombinedPdf(List<int> documentIds) =>
      _exporter.exportCombinedPdf(documentIds);

  @override
  Future<List<File>> exportSeparatePdfs(List<int> documentIds) =>
      _exporter.exportSeparatePdfs(documentIds);

  @override
  Future<File> exportProtectedPdf(int documentId, String password) =>
      _exporter.exportProtectedPdf(documentId, password);

  @override
  Future<File> exportPageAsImage(
    int documentId,
    int position, {
    ExportQuality quality = ExportQuality.original,
  }) => _exporter.exportPageAsImage(documentId, position, quality: quality);

  @override
  Future<List<File>> exportAllPagesAsImages(
    int documentId, {
    ExportQuality quality = ExportQuality.original,
  }) => _exporter.exportAllPagesAsImages(documentId, quality: quality);

  @override
  Future<File> exportRecognizedText(int documentId, int position) =>
      _exporter.exportRecognizedText(documentId, position);

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

  /// Regenerates the display ("flat") derivative from the PRISTINE base
  /// (enhance ∘ rotate ∘ crop) and returns its relative path, or null when the
  /// display equals the base (no rotation, no crop, no filter). NEVER writes
  /// the base. [corners] are in the display frame (post-rotation). Delegates to
  /// [PageDerivativePipeline] (P05 T05.5/CPLX-01).
  Future<String?> _writeFlat({
    required String relativeImagePath,
    required int quarterTurns,
    required CropCorners corners,
    required EnhancerMode mode,
    required String? existingFlatRel,
  }) => _pipeline.writeFlat(
    relativeImagePath: relativeImagePath,
    quarterTurns: quarterTurns,
    corners: corners,
    mode: mode,
    existingFlatRel: existingFlatRel,
  );

  /// Fetches the ([documentId], [position]) page row or throws (P10 DUP-01).
  /// Delegates to [PageDao] (P05 T05.3).
  Future<Page> _requirePage(
    int documentId,
    int position,
    String op, {
    bool export = false,
  }) => _pageDao.requirePage(documentId, position, op, export: export);

  /// Highest-position page row for [documentId], or null when it has none
  /// (P10 DUP-01). Delegates to [PageDao] (P05 T05.3).
  Future<Page?> _maxPositionPage(int documentId) =>
      _pageDao.maxPositionPage(documentId);

  @override
  Future<void> updatePageCorners(
    int documentId,
    int position,
    CropCorners corners,
  ) async {
    final page = await _requirePage(documentId, position, 'updatePageCorners');
    // Corners arrive already in the DISPLAY frame (post-rotation) from the
    // editor; rotation is unchanged by a crop.
    final flatRel = await _writeFlat(
      relativeImagePath: page.relativeImagePath,
      quarterTurns: page.rotationQuarterTurns,
      corners: corners,
      mode: EnhancerMode.fromIndex(page.enhancerMode),
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
    final row = await _requirePage(documentId, position, 'rotatePage');
    final turns = (row.rotationQuarterTurns + 1) % 4;
    // Keep the same physical crop in the newly-rotated display frame.
    final corners = (CropCorners.tryParse(row.corners) ?? CropCorners.fullFrame)
        .rotate90Cw();
    final isFullFrame = corners == CropCorners.fullFrame;
    final flatRel = await _writeFlat(
      relativeImagePath: row.relativeImagePath,
      quarterTurns: turns,
      corners: corners,
      mode: EnhancerMode.fromIndex(row.enhancerMode),
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
    final row = await _requirePage(documentId, position, 'updatePageEnhancer');
    final corners = CropCorners.tryParse(row.corners) ?? CropCorners.fullFrame;
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
      // Short read for the next position — no lock held across image work
      // (P03 SAFE-02).
      final maxRow = await _maxPositionPage(documentId);
      if (maxRow == null) {
        throw DocumentSaveException('document $documentId has no pages');
      }
      final newPosition = maxRow.position + 1;
      final rel = _fileStore.relativeFor(documentId, newPosition);
      final mode = enhancerModeOf(enhancer);
      final effective = corners ?? CropCorners.fullFrame;

      // Read/scrub/write/flat OUTSIDE any transaction.
      final raw = await File(capture.path).readAsBytes();
      final Uint8List scrubbed = _scrubber.scrub(ensureJpegBytes(raw));
      await _fileStore.writeRelative(rel, scrubbed); // pristine, unfiltered
      String? flatRel;
      try {
        flatRel = await _writeFlat(
          relativeImagePath: rel,
          quarterTurns: 0,
          corners: effective,
          mode: mode,
          existingFlatRel: null,
        );
      } catch (e, st) {
        flatRel = null;
        _logger.error(
          e,
          stackTrace: st,
          context: 'addPageToDocument: flat regen failed, saved base only',
        );
      }

      // Short transaction: insert the page row + bump modifiedAt.
      await _db.transaction(() async {
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
      });
      await _deleteTempSource(capture.path);
      _ocr.trigger(documentId, newPosition);
      return newPosition;
    } catch (e) {
      if (e is DocumentSaveException) rethrow;
      throw DocumentSaveException('addPage failed: $e');
    }
  }

  @override
  Future<int> deletePage(int documentId, int position) =>
      _ordering.deletePage(documentId, position);

  @override
  Future<void> replacePage(
    int documentId,
    int position,
    CapturedImage capture, {
    CropCorners? corners,
    ImageEnhancer? enhancer,
  }) async {
    try {
      final row = await _requirePage(documentId, position, 'replacePage');

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
  Future<void> reorderPages(int documentId, List<int> orderedPositions) =>
      _ordering.reorderPages(documentId, orderedPositions);

  @override
  Future<void> mergeInto(int targetDocumentId, int sourceDocumentId) =>
      _ordering.mergeInto(targetDocumentId, sourceDocumentId);

  @override
  Future<Document> splitAfter(int documentId, int position) =>
      _ordering.splitAfter(documentId, position);

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
    } catch (e, st) {
      // Best-effort: a lingering temp capture is harmless, but log it.
      _logger.error(e, stackTrace: st, context: 'temp capture cleanup failed');
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
