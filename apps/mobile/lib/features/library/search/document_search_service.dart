import 'package:drift/drift.dart';

import '../document.dart';
import '../document_file_store.dart';
import '../document_summary.dart';
import '../drift/app_database.dart' hide Document;
import 'fts_query_sanitizer.dart';

/// Owns library listing + search (P05 T05.6): the newest-first document
/// summaries and the FTS-ranked / LIKE-fallback query paths the repository used
/// to inline. Holds the DB + file store (for thumbnail paths) and the pure
/// [FtsQuerySanitizer]. Read-only — no mutations, so no transaction concerns.
class DocumentSearchService {
  final AppDatabase _db;
  final DocumentFileStore _fileStore;
  final FtsQuerySanitizer _sanitizer;

  const DocumentSearchService(
    this._db,
    this._fileStore, {
    FtsQuerySanitizer sanitizer = const FtsQuerySanitizer(),
  }) : _sanitizer = sanitizer; // ignore: prefer_initializing_formals

  /// All documents, newest first, with page count + first-page thumbnail.
  Future<List<DocumentSummary>> listSummaries() => _summaries();

  /// Documents whose name OR any page OCR matches [query]. A blank query
  /// returns the full list; short/degenerate queries use the LIKE fallback,
  /// otherwise the ranked trigram search.
  Future<List<DocumentSummary>> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return _summaries();
    final sanitized = _sanitizer.sanitize(query);
    // Trigram MATCH needs every term >= 3 chars; anything shorter (or a query
    // that sanitizes to nothing) falls back to the unranked LIKE scan so short
    // words still match as substrings.
    if (sanitized.useLike) return _searchByLike(q);
    return _searchRanked(q, sanitized.matchExpr);
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
    String matchExpr,
  ) async {
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

    // (2) first-page (lowest position) path per document — ONE aggregate query
    // (PERF-01), restricted to onlyIds when set, so we never scan the pages of
    // documents we aren't showing.
    final firstPathByDoc = await _firstPagePaths(onlyIds);

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

  /// First-page (lowest `position`) display path per document (PERF-01). Uses
  /// SQLite's bare-column MIN/MAX rule: `flat`/`img` are read from the row with
  /// `MIN(position)` in each `document_id` group, so ONE aggregate row per
  /// document is returned instead of scanning every page. Restricted to
  /// [onlyIds] when set. Preserves the `flat ?? image` precedence.
  Future<Map<int, String>> _firstPagePaths(Set<int>? onlyIds) async {
    if (onlyIds != null && onlyIds.isEmpty) return const {};
    final where = onlyIds == null
        ? ''
        : 'WHERE document_id IN (${List.filled(onlyIds.length, '?').join(', ')}) ';
    final rows = await _db
        .customSelect(
          'SELECT document_id AS did, MIN(position) AS mp, '
          'flat_relative_path AS flat, relative_image_path AS img '
          'FROM pages ${where}GROUP BY document_id',
          variables: onlyIds == null
              ? const []
              : [for (final id in onlyIds) Variable.withInt(id)],
          readsFrom: {_db.pages},
        )
        .get();
    return {
      for (final r in rows)
        r.read<int>('did'):
            r.readNullable<String>('flat') ?? r.read<String>('img'),
    };
  }
}
