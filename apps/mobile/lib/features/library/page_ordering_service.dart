import 'dart:io';

import 'package:drift/drift.dart';

import '../../core/logging/app_logger.dart';
import 'document.dart' hide Page;
import 'document_file_store.dart';
import 'document_repository.dart';
import 'drift/app_database.dart' hide Document;
import 'drift/page_dao.dart';

/// Owns the multi-row page-ordering operations (P05 T05.6): reorder, delete
/// (with renumber), merge, and split. These carry the P03 atomicity boundaries
/// — each commits ALL its row mutations in ONE transaction and cleans up any
/// append-only files on rollback — so the invariants are preserved verbatim
/// here. Holds the DB, file store, [PageDao], clock, and logger.
class PageOrderingService {
  final AppDatabase _db;
  final DocumentFileStore _fileStore;
  final PageDao _pageDao;
  final DateTime Function() _clock;
  final AppLogger _logger;

  const PageOrderingService(
    this._db,
    this._fileStore,
    this._pageDao,
    this._clock,
    this._logger,
  );

  Future<int> deletePage(int documentId, int position) async {
    final row = await _pageDao.requirePage(documentId, position, 'deletePage');
    // Count pages with one aggregate (was: fetch every row just to count) so we
    // can tell "only page" from "renumber survivors" (P10 CPLX-02).
    final remaining = await _pageDao.pageCount(documentId) - 1;

    await _db.transaction(() async {
      await (_db.delete(_db.pages)..where((t) => t.id.equals(row.id))).go();
      if (remaining > 0) {
        // Renumber survivors above the deleted position in ONE bulk UPDATE
        // (was O(pages) round-trips). `updates:` keeps drift streams live.
        await _pageDao.renumberAfterDelete(documentId, position);
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

  Future<void> mergeInto(int targetDocumentId, int sourceDocumentId) async {
    if (targetDocumentId == sourceDocumentId) {
      throw const DocumentSaveException('mergeInto: target == source');
    }
    final written = <String>[];
    try {
      final maxRow = await _pageDao.maxPositionPage(targetDocumentId);
      final targetMax = maxRow?.position ?? 0;
      final sourcePages =
          await (_db.select(_db.pages)
                ..where((p) => p.documentId.equals(sourceDocumentId))
                ..orderBy([(p) => OrderingTerm.asc(p.position)]))
              .get();

      // Copy files first (append-only new paths, outside the DB txn), building
      // the row inserts. Track every path so a rollback can clean them up.
      final inserts = <PagesCompanion>[];
      var k = 0;
      for (final src in sourcePages) {
        k++;
        final imageRel = _fileStore.mergedRelativeFor(
          targetDocumentId,
          sourceDocumentId,
          src.position,
        );
        final flatRel = await _copyPageFiles(src, imageRel, written);
        inserts.add(
          _cloneSourcePage(
            src,
            documentId: targetDocumentId,
            position: targetMax + k,
            imageRel: imageRel,
            flatRel: flatRel,
          ),
        );
      }
      // Atomic: append the pages AND remove the source's rows in ONE txn, so a
      // crash can never leave the pages living in BOTH documents (P03 SAFE-01a).
      // The source-row deletion is inlined here rather than via the post-txn
      // deleteDocument() so it commits together with the inserts.
      await _db.transaction(() async {
        for (final c in inserts) {
          await _db.into(_db.pages).insert(c);
        }
        await (_db.update(_db.documents)
              ..where((d) => d.id.equals(targetDocumentId)))
            .write(DocumentsCompanion(modifiedAt: Value(_clock().toUtc())));
        await (_db.delete(
          _db.pages,
        )..where((t) => t.documentId.equals(sourceDocumentId))).go();
        await (_db.delete(
          _db.documents,
        )..where((d) => d.id.equals(sourceDocumentId))).go();
      });
    } catch (e) {
      await _cleanupWrittenFiles(written, e); // rolled back — no orphan files
      if (e is DocumentSaveException) rethrow;
      throw DocumentSaveException('mergeInto failed: $e');
    }
    // Source ROWS are gone (committed above). Best-effort remove its dir; worst
    // case is a harmless orphan directory (no row references it).
    await _fileStore.deleteDocumentDir(sourceDocumentId);
  }

  Future<Document> splitAfter(int documentId, int position) async {
    int? newId;
    final written = <String>[];
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
      // Reserve the new document id — needed to name the copied files. If any
      // later step fails, this row (and its files) are removed in the catch, so
      // no half-built split ever becomes visible (P03 SAFE-01b).
      newId = await _db
          .into(_db.documents)
          .insert(
            DocumentsCompanion.insert(
              name: newName,
              createdAt: now,
              modifiedAt: now,
            ),
          );

      final moved = pages.where((p) => p.position > position).toList();
      // Copy the moved pages' files first (append-only), OUTSIDE the txn.
      final inserts = <PagesCompanion>[];
      var k = 0;
      for (final src in moved) {
        k++;
        final imageRel = _fileStore.relativeFor(newId, k);
        final flatRel = await _copyPageFiles(src, imageRel, written);
        inserts.add(
          _cloneSourcePage(
            src,
            documentId: newId,
            position: k,
            imageRel: imageRel,
            flatRel: flatRel,
          ),
        );
      }

      // Atomic: insert the moved rows into the new doc AND delete them from the
      // source in ONE txn, so a crash can never duplicate a page across both
      // documents (P03 SAFE-01b).
      await _db.transaction(() async {
        for (final c in inserts) {
          await _db.into(_db.pages).insert(c);
        }
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
      // Roll back: drop the copied files AND the reserved (now-empty) new doc,
      // so a failed split leaves no orphan document or duplicated pages.
      await _cleanupWrittenFiles(written, e);
      if (newId != null) {
        try {
          await _db.transaction(() async {
            await (_db.delete(
              _db.pages,
            )..where((t) => t.documentId.equals(newId!))).go();
            await (_db.delete(
              _db.documents,
            )..where((d) => d.id.equals(newId!))).go();
          });
        } catch (_) {
          /* best-effort */
        }
        await _fileStore.deleteDocumentDir(newId);
      }
      if (e is DocumentSaveException) rethrow;
      throw DocumentSaveException('splitAfter failed: $e');
    }
  }

  /// Best-effort delete of the append-only files written during a merge/split
  /// that then failed, so a rolled-back op leaves no orphan files (P03 SAFE-01,
  /// T03.5). Never throws; reports the triggering [cause] via [_logger].
  Future<void> _cleanupWrittenFiles(List<String> relPaths, Object cause) async {
    for (final rel in relPaths) {
      try {
        final f = _fileStore.absoluteFor(rel);
        if (await f.exists()) await f.delete();
      } catch (_) {
        /* best-effort — a leftover file is harmless, a thrown cleanup is not */
      }
    }
    _logger.error(
      cause,
      context:
          'rolled back file writes; cleaned ${relPaths.length} orphan file(s)',
    );
  }

  /// Copies [src]'s base image (and its flat derivative, if any) to [imageRel]
  /// (+ the matching flat path), appending every written relative path to
  /// [written] for rollback cleanup. Returns the new flat path, or null when
  /// [src] had none. Shared by mergeInto/splitAfter (P10 DUP-02).
  Future<String?> _copyPageFiles(
    Page src,
    String imageRel,
    List<String> written,
  ) async {
    final srcBytes = await _fileStore
        .absoluteFor(src.relativeImagePath)
        .readAsBytes();
    await _fileStore.writeRelative(imageRel, srcBytes);
    written.add(imageRel);
    if (src.flatRelativePath == null) return null;
    final flatBytes = await _fileStore
        .absoluteFor(src.flatRelativePath!)
        .readAsBytes();
    final flatRel = _fileStore.flatForImage(imageRel);
    await _fileStore.writeRelative(flatRel, flatBytes);
    written.add(flatRel);
    return flatRel;
  }

  /// A [PagesCompanion] cloning ALL carried columns of [src] under a new
  /// [documentId]/[position] with the copied [imageRel]/[flatRel] paths, so a
  /// future column is added in ONE place, not two (P10 DUP-02).
  PagesCompanion _cloneSourcePage(
    Page src, {
    required int documentId,
    required int position,
    required String imageRel,
    required String? flatRel,
  }) => PagesCompanion.insert(
    documentId: documentId,
    position: position,
    relativeImagePath: imageRel,
    corners: Value(src.corners),
    flatRelativePath: Value(flatRel),
    ocrText: Value(src.ocrText),
    ocrBoxes: Value(src.ocrBoxes),
    rotationQuarterTurns: Value(src.rotationQuarterTurns),
    enhancerMode: Value(src.enhancerMode),
  );
}
