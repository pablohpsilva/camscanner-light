import 'dart:io';

import 'package:drift/drift.dart';

import '../../scan/captured_image.dart';
import '../crop_corners.dart';
import '../document.dart';
import '../document_file_store.dart';
import '../document_repository.dart';
import '../document_summary.dart';
import '../image_enhancer.dart';
import '../image_metadata_scrubber.dart';
import '../image_warper.dart';
import '../page_image.dart';
import '../pdf/pdf_builder.dart';
import 'app_database.dart' hide Document;

/// Drift-backed [DocumentRepository]. Scrubs the capture, writes the file, and
/// inserts the rows inside a single transaction so the DB never holds a partial
/// record. Stores RELATIVE image paths.
class DriftDocumentRepository implements DocumentRepository {
  final AppDatabase _db;
  final ImageMetadataScrubber _scrubber;
  final DocumentFileStore _fileStore;
  final DateTime Function() _clock;
  final PdfBuilder _pdfBuilder;
  final ImageWarper _warper;

  DriftDocumentRepository({
    required AppDatabase db,
    required ImageMetadataScrubber scrubber,
    required DocumentFileStore fileStore,
    required DateTime Function() clock,
    required PdfBuilder pdfBuilder,
    required ImageWarper warper,
  })  : _db = db, // ignore: prefer_initializing_formals
        _scrubber = scrubber, // ignore: prefer_initializing_formals
        _fileStore = fileStore, // ignore: prefer_initializing_formals
        _clock = clock, // ignore: prefer_initializing_formals
        _pdfBuilder = pdfBuilder, // ignore: prefer_initializing_formals
        _warper = warper; // ignore: prefer_initializing_formals

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
        final docId = await _db.into(_db.documents).insert(
              DocumentsCompanion.insert(
                  name: name, createdAt: createdUtc, modifiedAt: createdUtc),
            );
        final rel = _fileStore.relativeFor(docId, 1);
        late final Uint8List scrubbed;
        try {
          final raw = await File(capture.path).readAsBytes();
          scrubbed = _scrubber.scrub(Uint8List.fromList(raw));
          // G1: for full-frame (no warp), apply enhancement to the original
          // before writing. Each ImageEnhancer is responsible for baking EXIF
          // orientation before encoding (encodeJpg strips EXIF).
          final isFullFrame = corners == null || corners == CropCorners.fullFrame;
          Uint8List bytesToStore = scrubbed;
          if (enhancer != null && isFullFrame) {
            try {
              bytesToStore = await enhancer.enhance(scrubbed);
            } catch (_) {} // silent: use unenhanced scrubbed bytes
          }
          await _fileStore.writeRelative(rel, bytesToStore);
        } catch (e) {
          await _fileStore.deleteDocumentDir(docId); // best-effort cleanup
          rethrow; // rolls back the inserted document row
        }
        // E2 + G1: perspective-flatten, then enhance the flat.
        // Original (rel) is already on disk for the full-frame path.
        String? flatRel;
        if (corners != null && corners != CropCorners.fullFrame) {
          try {
            Uint8List? flat = await _warper.warp(scrubbed, corners);
            if (flat != null) {
              // Orientation already baked by warper — enhancer gets clean bytes.
              Uint8List flatBytes = flat;
              if (enhancer != null) {
                try {
                  flatBytes = await enhancer.enhance(flat);
                } catch (_) {} // silent: store unenhanced warp result
              }
              flatRel = _fileStore.flatRelativeFor(docId, 1);
              await _fileStore.writeRelative(flatRel, flatBytes);
            }
          } catch (_) {/* WarpException or IO — flat stays null, save proceeds */}
        }
        await _db.into(_db.pages).insert(
              PagesCompanion.insert(
                  documentId: docId,
                  position: 1,
                  relativeImagePath: rel,
                  corners: Value(corners?.toStorage()),
                  flatRelativePath: Value(flatRel)),
            );
        return Document(
            id: docId,
            name: name,
            createdAt: createdUtc,
            modifiedAt: createdUtc);
      });
      await _deleteTempSource(capture.path);
      return doc;
    } catch (e) {
      throw DocumentSaveException('save failed: $e');
    }
  }

  @override
  Future<List<DocumentSummary>> listDocumentSummaries() async {
    // (1) page count per document, newest doc first — one grouped query.
    final pageCount = _db.pages.id.count();
    final query = _db.select(_db.documents).join([
      leftOuterJoin(_db.pages, _db.pages.documentId.equalsExp(_db.documents.id)),
    ])
      ..addColumns([pageCount])
      ..groupBy([_db.documents.id])
      ..orderBy([OrderingTerm.desc(_db.documents.createdAt)]);
    final rows = await query.get();

    // (2) lowest-position page path per document — one query, no N+1.
    final pages = await (_db.select(_db.pages)
          ..orderBy([(t) => OrderingTerm.asc(t.position)]))
        .get();
    final firstPathByDoc = <int, String>{};
    for (final pg in pages) {
      firstPathByDoc.putIfAbsent(
          pg.documentId, () => pg.flatRelativePath ?? pg.relativeImagePath);
    }

    return rows.map((row) {
      final d = row.readTable(_db.documents);
      final rel = firstPathByDoc[d.id];
      return DocumentSummary(
        document: Document(
            id: d.id,
            name: d.name,
            createdAt: d.createdAt,
            modifiedAt: d.modifiedAt),
        pageCount: row.read(pageCount)!,
        thumbnailPath: rel == null ? null : _fileStore.absoluteFor(rel).path,
      );
    }).toList();
  }

  @override
  Future<List<PageImage>> getDocumentPages(int documentId) async {
    final pages = await (_db.select(_db.pages)
          ..where((t) => t.documentId.equals(documentId))
          ..orderBy([(t) => OrderingTerm.asc(t.position)]))
        .get();
    return pages
        .map((pg) => PageImage(
              position: pg.position,
              imagePath: _fileStore.absoluteFor(pg.relativeImagePath).path,
              corners: CropCorners.tryParse(pg.corners) ?? CropCorners.fullFrame,
              flatImagePath: pg.flatRelativePath == null
                  ? null
                  : _fileStore.absoluteFor(pg.flatRelativePath!).path,
            ))
        .toList();
  }

  @override
  Future<void> deleteDocument(int documentId) async {
    // Row-first: the DB delete is authoritative. Explicit page delete (not
    // relying solely on the FK cascade pragma), then the document row.
    await _db.transaction(() async {
      await (_db.delete(_db.pages)
            ..where((t) => t.documentId.equals(documentId)))
          .go();
      await (_db.delete(_db.documents)..where((t) => t.id.equals(documentId)))
          .go();
    });
    // Best-effort file cleanup AFTER commit. Worst case = harmless orphan files
    // (no row references them). deleteDocumentDir guards dir-absent.
    await _fileStore.deleteDocumentDir(documentId);
  }

  @override
  Future<File> exportPdf(int documentId) async {
    final pages = await getDocumentPages(documentId);
    if (pages.isEmpty) {
      throw const DocumentExportException('export failed: no pages');
    }
    try {
      final bytes = await _pdfBuilder.build(pages);
      final rel = _fileStore.pdfRelativeFor(documentId);
      await _fileStore.writeRelative(rel, bytes);
      return _fileStore.absoluteFor(rel);
    } catch (e) {
      throw DocumentExportException('export failed: $e');
    }
  }

  @override
  Future<Document> rename(int documentId, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) {
      throw const DocumentRenameException('rename failed: empty name');
    }
    final modifiedUtc = _clock().toUtc();
    final updated = await (_db.update(_db.documents)
          ..where((t) => t.id.equals(documentId)))
        .write(DocumentsCompanion(
            name: Value(trimmed), modifiedAt: Value(modifiedUtc)));
    if (updated == 0) {
      throw const DocumentRenameException('rename failed: no such document');
    }
    final row = await (_db.select(_db.documents)
          ..where((t) => t.id.equals(documentId)))
        .getSingle();
    return Document(
      id: row.id,
      name: row.name,
      createdAt: row.createdAt,
      modifiedAt: row.modifiedAt,
    );
  }

  @override
  Future<void> updatePageCorners(
      int documentId, int position, CropCorners corners) async {
    final page = await (_db.select(_db.pages)
          ..where((t) =>
              t.documentId.equals(documentId) & t.position.equals(position)))
        .getSingleOrNull();
    if (page == null) {
      throw DocumentSaveException(
          'updatePageCorners: no page ($documentId, $position)');
    }

    if (corners == CropCorners.fullFrame) {
      final flatRel = page.flatRelativePath;
      if (flatRel != null) {
        try {
          await _fileStore.absoluteFor(flatRel).delete();
        } on FileSystemException {/* already gone — fine */}
      }
      await (_db.update(_db.pages)
            ..where((t) =>
                t.documentId.equals(documentId) & t.position.equals(position)))
          .write(PagesCompanion(
              corners: const Value<String?>(null),
              flatRelativePath: const Value<String?>(null)));
      return;
    }

    // Non-fullFrame: read original JPEG, warp, write flat, update row.
    final bytes =
        await _fileStore.absoluteFor(page.relativeImagePath).readAsBytes();
    final flat = await _warper.warp(bytes, corners);
    if (flat == null) return; // warper returned null — no-op here
    final flatRel = _fileStore.flatRelativeFor(documentId, position);
    await _fileStore.writeRelative(flatRel, flat);
    await (_db.update(_db.pages)
          ..where((t) =>
              t.documentId.equals(documentId) & t.position.equals(position)))
        .write(PagesCompanion(
            corners: Value(corners.toStorage()),
            flatRelativePath: Value(flatRel)));
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
        final maxRow = await (_db.select(_db.pages)
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
        final Uint8List scrubbed = _scrubber.scrub(raw);
        final isFullFrame =
            corners == null || corners == CropCorners.fullFrame;
        Uint8List bytesToStore = scrubbed;
        if (enhancer != null && isFullFrame) {
          try {
            bytesToStore = await enhancer.enhance(scrubbed);
          } catch (_) {}
        }
        await _fileStore.writeRelative(rel, bytesToStore);
        String? flatRel;
        if (corners != null && corners != CropCorners.fullFrame) {
          try {
            Uint8List? flat = await _warper.warp(scrubbed, corners);
            if (flat != null) {
              Uint8List flatBytes = flat;
              if (enhancer != null) {
                try {
                  flatBytes = await enhancer.enhance(flat);
                } catch (_) {}
              }
              flatRel = _fileStore.flatRelativeFor(documentId, newPosition);
              await _fileStore.writeRelative(flatRel, flatBytes);
            }
          } catch (_) {}
        }
        await _db.into(_db.pages).insert(
              PagesCompanion.insert(
                documentId: documentId,
                position: newPosition,
                relativeImagePath: rel,
                corners: Value(corners?.toStorage()),
                flatRelativePath: Value(flatRel),
              ),
            );
        await (_db.update(_db.documents)
              ..where((d) => d.id.equals(documentId)))
            .write(DocumentsCompanion(modifiedAt: Value(_clock().toUtc())));
        return newPosition;
      });
      await _deleteTempSource(capture.path);
      return position;
    } catch (e) {
      if (e is DocumentSaveException) rethrow;
      throw DocumentSaveException('addPage failed: $e');
    }
  }

  @override
  Future<void> reorderPages(int documentId, List<int> orderedPositions) async {
    // Pre-fetch rows before the transaction to build a position→rowId map.
    // Updates inside the transaction use the primary key (id) to avoid
    // position-value conflicts when two pages swap positions.
    final rows = await (_db.select(_db.pages)
          ..where((t) => t.documentId.equals(documentId))
          ..orderBy([(t) => OrderingTerm.asc(t.position)]))
        .get();
    if (rows.isEmpty) {
      throw DocumentSaveException(
          'reorderPages: no pages for $documentId');
    }
    final posToId = {for (final r in rows) r.position: r.id};

    await _db.transaction(() async {
      for (var i = 0; i < orderedPositions.length; i++) {
        final oldPosition = orderedPositions[i];
        final rowId = posToId[oldPosition];
        if (rowId == null) continue; // unknown position — skip
        final newPosition = i + 1;
        if (oldPosition == newPosition) continue; // no change needed
        await (_db.update(_db.pages)
              ..where((t) => t.id.equals(rowId)))
            .write(PagesCompanion(position: Value(newPosition)));
      }
      await (_db.update(_db.documents)
            ..where((d) => d.id.equals(documentId)))
          .write(DocumentsCompanion(modifiedAt: Value(_clock().toUtc())));
    });
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
    } catch (_) {/* best-effort */}
  }
}
