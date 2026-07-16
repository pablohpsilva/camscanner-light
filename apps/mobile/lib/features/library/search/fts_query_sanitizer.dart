/// Immutable result of sanitizing a raw search query for FTS5 (P05 SAFE-06).
class SanitizedQuery {
  /// Safe, non-empty search terms: FTS operator characters stripped from each,
  /// bareword boolean keywords dropped. Never contains FTS syntax.
  final List<String> terms;

  /// The trigram `MATCH` expression — each term quoted and AND-joined
  /// (`"foo" AND "bar"`). Empty string when [terms] is empty.
  final String matchExpr;

  /// The `LIKE` pattern for the raw (trimmed) query: `%query%`. Operators are
  /// intentionally NOT stripped here — LIKE is a literal substring scan.
  final String likePattern;

  /// True when the query must fall back to the unranked LIKE scan: no usable
  /// terms, or any term shorter than the trigram minimum (3 chars).
  final bool useLike;

  const SanitizedQuery({
    required this.terms,
    required this.matchExpr,
    required this.likePattern,
    required this.useLike,
  });
}

/// Pure value transformer: raw query → [SanitizedQuery]. The single, isolated,
/// exhaustively-testable home for FTS query sanitization (P05 SAFE-06) — it
/// prevents FTS5 syntax/injection from reaching `MATCH`. No DB dependency, so
/// the injection-safety logic can be unit-tested in isolation.
class FtsQuerySanitizer {
  const FtsQuerySanitizer();

  // FTS5 operator characters stripped from every term before it reaches MATCH.
  static final RegExp _ftsOps = RegExp(r'''["*:^()\-]''');
  static const Set<String> _ftsKeywords = {'and', 'or', 'not', 'near'};

  // Trigram MATCH needs every term at least this many characters.
  static const int _minTrigram = 3;

  SanitizedQuery sanitize(String query) {
    final q = query.trim();
    // Raw query → safe search terms: operator chars removed, bareword boolean
    // keywords dropped, empties discarded. Never yields FTS syntax.
    final terms = q
        .split(RegExp(r'\s+'))
        .map((t) => t.replaceAll(_ftsOps, ''))
        .where((t) => t.isNotEmpty && !_ftsKeywords.contains(t.toLowerCase()))
        .toList();
    return SanitizedQuery(
      terms: terms,
      matchExpr: terms.map((t) => '"$t"').join(' AND '),
      likePattern: '%$q%',
      useLike: terms.isEmpty || terms.any((t) => t.length < _minTrigram),
    );
  }
}
