import 'package:drift/drift.dart';

import '../crop_corners.dart';
import '../document_file_store.dart';
import '../document_repository.dart';
import '../enhancer_mode.dart';
import '../ocr/ocr_result.dart';
import '../page_image.dart';
import 'app_database.dart';

/// The single home for the drift page-row access the repository used to inline
/// (P05 T05.3). Pure queries + row→[PageImage] mapping; holds the database and
/// the file store (to resolve absolute paths). Row mutations that must be
/// atomic stay in the services that own their transaction boundaries — a DAO
/// participates in an ambient `_db.transaction` because it shares [_db].
class PageDao {
  final AppDatabase _db;
  final DocumentFileStore _fileStore;
  const PageDao(this._db, this._fileStore);

  /// Fetches the ([documentId], [position]) page row or throws (P10 DUP-01).
  /// [op] is the message prefix; when [export] is true the failure is a
  /// [DocumentExportException] (the export methods), else a
  /// [DocumentSaveException].
  Future<Page> requirePage(
    int documentId,
    int position,
    String op, {
    bool export = false,
  }) async {
    final row =
        await (_db.select(_db.pages)..where(
              (t) =>
                  t.documentId.equals(documentId) & t.position.equals(position),
            ))
            .getSingleOrNull();
    if (row != null) return row;
    final message = '$op: no page ($documentId, $position)';
    throw export
        ? DocumentExportException(message)
        : DocumentSaveException(message);
  }

  /// Highest-position page row for [documentId], or null when it has none
  /// (P10 DUP-01). Callers decide whether "no pages" is an error.
  Future<Page?> maxPositionPage(int documentId) =>
      (_db.select(_db.pages)
            ..where((p) => p.documentId.equals(documentId))
            ..orderBy([(p) => OrderingTerm.desc(p.position)])
            ..limit(1))
          .getSingleOrNull();

  /// Pages of [documentId], position ascending, mapped to [PageImage] with
  /// ABSOLUTE image/flat paths resolved at read time.
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
            enhancerMode: EnhancerMode.fromIndex(pg.enhancerMode),
            flatImagePath: pg.flatRelativePath == null
                ? null
                : _fileStore.absoluteFor(pg.flatRelativePath!).path,
            ocrText: pg.ocrText,
            ocrWords: OcrResult.decodeBoxes(pg.ocrBoxes),
          ),
        )
        .toList();
  }

  /// Number of pages of [documentId] — one aggregate query (P10 CPLX-02), so a
  /// caller can tell "only page" from "renumber survivors" without fetching
  /// every row.
  Future<int> pageCount(int documentId) async {
    final countExp = _db.pages.id.count();
    final row =
        await (_db.selectOnly(_db.pages)
              ..addColumns([countExp])
              ..where(_db.pages.documentId.equals(documentId)))
            .getSingle();
    return row.read(countExp) ?? 0;
  }

  /// Renumbers survivors above a just-deleted [position] in ONE bulk UPDATE
  /// (P10 CPLX-02). `updates:` keeps drift streams live. Call inside the
  /// deleting transaction.
  Future<int> renumberAfterDelete(int documentId, int position) =>
      _db.customUpdate(
        'UPDATE pages SET position = position - 1 '
        'WHERE document_id = ? AND position > ?',
        variables: [Variable.withInt(documentId), Variable.withInt(position)],
        updates: {_db.pages},
      );
}
