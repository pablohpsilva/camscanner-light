import 'dart:io';

import 'package:drift/drift.dart';

import '../../scan/captured_image.dart';
import '../document.dart';
import '../document_file_store.dart';
import '../document_repository.dart';
import '../document_summary.dart';
import '../image_metadata_scrubber.dart';
import 'app_database.dart' hide Document;

/// Drift-backed [DocumentRepository]. Scrubs the capture, writes the file, and
/// inserts the rows inside a single transaction so the DB never holds a partial
/// record. Stores RELATIVE image paths.
class DriftDocumentRepository implements DocumentRepository {
  final AppDatabase _db;
  final ImageMetadataScrubber _scrubber;
  final DocumentFileStore _fileStore;
  final DateTime Function() _clock;

  DriftDocumentRepository({
    required AppDatabase db,
    required ImageMetadataScrubber scrubber,
    required DocumentFileStore fileStore,
    required DateTime Function() clock,
  })  : _db = db, // ignore: prefer_initializing_formals
        _scrubber = scrubber, // ignore: prefer_initializing_formals
        _fileStore = fileStore, // ignore: prefer_initializing_formals
        _clock = clock; // ignore: prefer_initializing_formals

  @override
  Future<Document> createFromCapture(CapturedImage capture) async {
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
        try {
          final raw = await File(capture.path).readAsBytes();
          final scrubbed = _scrubber.scrub(Uint8List.fromList(raw));
          await _fileStore.writeRelative(rel, scrubbed);
        } catch (e) {
          await _fileStore.deleteDocumentDir(docId); // best-effort cleanup
          rethrow; // rolls back the inserted document row
        }
        await _db.into(_db.pages).insert(
              PagesCompanion.insert(
                  documentId: docId, position: 1, relativeImagePath: rel),
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
      firstPathByDoc.putIfAbsent(pg.documentId, () => pg.relativeImagePath);
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
