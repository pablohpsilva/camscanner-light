import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart';

import '../../scan/captured_image.dart';
import '../crop_corners.dart';
import '../document.dart';
import '../document_file_store.dart';
import '../document_repository.dart';
import '../document_summary.dart';
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
  Future<Document> createFromCapture(CapturedImage capture, {CropCorners? corners}) async {
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
        // Hoist scrubbed out of try so it's in scope for the warp block.
        late final Uint8List scrubbed;
        try {
          final raw = await File(capture.path).readAsBytes();
          scrubbed = _scrubber.scrub(Uint8List.fromList(raw));
          await _fileStore.writeRelative(rel, scrubbed);
        } catch (e) {
          await _fileStore.deleteDocumentDir(docId); // best-effort cleanup
          rethrow; // rolls back the inserted document row
        }
        // E2: perspective-flatten best-effort. Original is already on disk.
        String? flatRel;
        if (corners != null && corners != CropCorners.fullFrame) {
          try {
            final flat = await _warper.warp(scrubbed, corners);
            if (flat != null) {
              flatRel = _fileStore.flatRelativeFor(docId, 1);
              await _fileStore.writeRelative(flatRel, flat);
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
