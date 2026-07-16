import 'package:drift/drift.dart';

import '../../../core/logging/app_logger.dart';
import '../document_file_store.dart';
import '../drift/app_database.dart';
import '../drift/page_dao.dart';
import 'ocr_engine.dart';

/// Owns page OCR (P05 T05.7): recognizing a page's display image and caching
/// the text + word boxes, plus the fire-and-forget post-save trigger. OCR is a
/// derived, re-runnable cache — never user content — so this deliberately does
/// NOT bump `modifiedAt` and must never fail a save. Holds the DB, file store,
/// [PageDao], the engine, and the logger.
class OcrService {
  final AppDatabase _db;
  final DocumentFileStore _fileStore;
  final PageDao _pageDao;
  final OcrEngine _engine;
  final AppLogger _logger;

  const OcrService(
    this._db,
    this._fileStore,
    this._pageDao,
    this._engine,
    this._logger,
  );

  /// Recognizes the page at ([documentId], [position]) and caches its text +
  /// boxes. Each run OVERWRITES the cached OCR (so a NoOp/failed pass clears
  /// it). Throws [DocumentSaveException] (via [PageDao]) when the row is missing.
  Future<void> runOcr(int documentId, int position) async {
    final row = await _pageDao.requirePage(documentId, position, 'runOcr');
    // Recognize the DISPLAY image (flat derivative if present, else original).
    final srcRel = row.flatRelativePath ?? row.relativeImagePath;
    final bytes = await _fileStore.absoluteFor(srcRel).readAsBytes();
    final result = await _engine.recognize(bytes);
    await (_db.update(_db.pages)..where((t) => t.id.equals(row.id))).write(
      PagesCompanion(
        ocrText: Value(result.text),
        ocrBoxes: Value(result.encodeBoxes()),
      ),
    );
  }

  /// Fire-and-forget OCR after a save. Swallows errors — OCR must never fail a
  /// save — and does not run for the NoOp engine (skips wasted work in tests).
  void trigger(int documentId, int position) {
    if (_engine is NoOpOcrEngine) return;
    // ignore: discarded_futures
    runOcr(documentId, position).catchError((Object e, StackTrace st) {
      // OCR is a re-runnable cache: never fail a save, but no longer silent.
      _logger.error(e, stackTrace: st, context: 'background OCR failed');
    });
  }
}
