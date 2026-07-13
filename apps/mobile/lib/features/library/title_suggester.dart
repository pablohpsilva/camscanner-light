/// Suggests a document title from recognized OCR text. Pure — no DB, no native
/// deps — so it is exhaustively unit-testable on the host. Returns the first
/// "meaningful" line (has letters/digits, >= 3 chars after internal whitespace
/// is collapsed and edge whitespace/punctuation are trimmed), capped at
/// [_maxLen] with an ellipsis, or null when nothing usable.
class TitleSuggester {
  const TitleSuggester();

  static const int _maxLen = 40;
  static final RegExp _ws = RegExp(r'\s+');
  static final RegExp _edgePunct = RegExp(r'^[^A-Za-z0-9]+|[^A-Za-z0-9]+$');
  static final RegExp _alnum = RegExp(r'[A-Za-z0-9]');

  String? suggest(String ocrText) {
    for (final rawLine in ocrText.split('\n')) {
      final collapsed = rawLine.replaceAll(_ws, ' ').trim();
      final cleaned = collapsed.replaceAll(_edgePunct, '');
      if (cleaned.length < 3) continue;
      if (!_alnum.hasMatch(cleaned)) continue;
      if (cleaned.length <= _maxLen) return cleaned;
      return '${cleaned.substring(0, _maxLen).trimRight()}…';
    }
    return null;
  }
}
