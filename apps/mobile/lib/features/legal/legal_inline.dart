/// One run of inline text from a legal document: plain, bold, or a link.
class LegalInlineSpan {
  final String text;
  final bool bold;
  final String? url;
  const LegalInlineSpan(this.text, {this.bold = false, this.url});
}

// Must stay behaviourally identical to parseInline() in
// libs/legal-content/src/inline.mjs — the two suites share fixtures.
//
// Bold content must begin AND end with non-whitespace; the `??` (lazy
// optional) is load-bearing — without it, a stray `**` pairs with the far
// end of a later, unrelated `**bold**` instead of leaving itself literal.
final _pattern = RegExp(
  r'\*\*(\S(?:[\s\S]*?\S)??)\*\*|\[([^\]]+)\]\(([^)\s]+)\)',
);

/// Splits [text] into spans. Only `**bold**` and `[label](url)` are markup;
/// anything else is literal.
List<LegalInlineSpan> parseLegalInline(String text) {
  final spans = <LegalInlineSpan>[];
  var last = 0;
  for (final m in _pattern.allMatches(text)) {
    if (m.start > last) {
      spans.add(LegalInlineSpan(text.substring(last, m.start)));
    }
    if (m.group(1) != null) {
      spans.add(LegalInlineSpan(m.group(1)!, bold: true));
    } else {
      spans.add(LegalInlineSpan(m.group(2)!, url: m.group(3)));
    }
    last = m.end;
  }
  if (last < text.length) spans.add(LegalInlineSpan(text.substring(last)));
  return spans;
}
