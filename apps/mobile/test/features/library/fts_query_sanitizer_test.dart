import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/search/fts_query_sanitizer.dart';

/// Exhaustive characterization of the FTS query sanitizer (P05 SAFE-06). These
/// cases freeze the EXACT behavior the God repository had inline in
/// `_searchTerms`/`_ftsOps`/`_ftsKeywords`/`searchDocuments`, so extracting it
/// changes nothing observable. Sanitization is security-adjacent: it must never
/// let FTS5 syntax reach the `MATCH` expression.
void main() {
  const s = FtsQuerySanitizer();

  group('terms', () {
    test('splits on whitespace, trims the query', () {
      expect(s.sanitize('  foo   bar  ').terms, ['foo', 'bar']);
    });

    test('strips FTS operator chars from within a term', () {
      // " * : ^ ( ) - are all removed.
      expect(s.sanitize('"foo*"').terms, ['foo']);
      expect(s.sanitize('a:b').terms, ['ab']);
      expect(s.sanitize('(foo)').terms, ['foo']);
      expect(s.sanitize('foo-bar').terms, ['foobar']);
      expect(s.sanitize('a^b').terms, ['ab']);
    });

    test('drops bareword boolean keywords (case-insensitive)', () {
      expect(s.sanitize('and or not near').terms, isEmpty);
      expect(s.sanitize('AND foo OR bar').terms, ['foo', 'bar']);
      expect(s.sanitize('Near baz').terms, ['baz']);
    });

    test('drops tokens that sanitize away to empty', () {
      expect(s.sanitize('"* () foo').terms, ['foo']);
      expect(s.sanitize('"*:^()-').terms, isEmpty);
    });

    test('empty / whitespace query yields no terms', () {
      expect(s.sanitize('').terms, isEmpty);
      expect(s.sanitize('   ').terms, isEmpty);
    });
  });

  group('matchExpr', () {
    test('quotes each term and AND-joins them', () {
      expect(s.sanitize('foo bar').matchExpr, '"foo" AND "bar"');
      expect(s.sanitize('abc').matchExpr, '"abc"');
    });

    test('is empty when there are no terms', () {
      expect(s.sanitize('  ').matchExpr, '');
      expect(s.sanitize('and or').matchExpr, '');
    });

    test('neutralizes an attempted FTS-syntax injection', () {
      // Classic injection shape: quotes/operators that would break out of the
      // quoted term. After sanitization the expression is ONLY quoted terms
      // AND-joined — no stray quote, star, colon, caret, paren, or hyphen.
      final expr = s.sanitize('foo" OR bar:* ^(x)-y').matchExpr;
      // OR is dropped (bareword keyword); the rest are stripped of operators.
      expect(expr, '"foo" AND "bar" AND "xy"');
      // No operator character survives outside the wrapping quotes.
      for (final term in expr.split(' AND ')) {
        final inner = term.substring(1, term.length - 1); // unwrap quotes
        expect(
          RegExp(r'''["*:^()\-]''').hasMatch(inner),
          isFalse,
          reason: 'operator leaked into MATCH term: $term',
        );
      }
    });
  });

  group('likePattern', () {
    test('wraps the TRIMMED raw query in %...% (not the terms)', () {
      expect(s.sanitize('  foo bar  ').likePattern, '%foo bar%');
      // Operators are NOT stripped for LIKE — it is a literal substring scan.
      expect(s.sanitize('a:b').likePattern, '%a:b%');
    });
  });

  group('useLike', () {
    test('true when there are no usable terms', () {
      expect(s.sanitize('').useLike, isTrue);
      expect(s.sanitize('and or not').useLike, isTrue);
    });

    test('true when ANY term is shorter than the trigram minimum (3)', () {
      expect(s.sanitize('ab').useLike, isTrue);
      expect(s.sanitize('foo ab').useLike, isTrue); // one short term taints all
    });

    test('false when every term is >= 3 chars', () {
      expect(s.sanitize('foo').useLike, isFalse);
      expect(s.sanitize('foo bar baz').useLike, isFalse);
    });
  });
}
