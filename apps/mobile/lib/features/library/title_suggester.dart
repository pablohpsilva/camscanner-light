/// Suggests a document title from recognized OCR text. Pure — no DB, no native
/// deps — so it is exhaustively unit-testable on the host. Returns the first
/// "meaningful" line (has letters/digits, >= 3 chars after edge whitespace and
/// edge punctuation are trimmed; internal whitespace is left as-is), capped at
/// [_maxLen] with an ellipsis, or null when nothing usable.
class TitleSuggester {
  const TitleSuggester();

  static const int _maxLen = 40;
  static final RegExp _edgePunct = RegExp(r'^[^A-Za-z0-9]+|[^A-Za-z0-9]+$');
  static final RegExp _alnum = RegExp(r'[A-Za-z0-9]');

  String? suggest(String ocrText) {
    for (final rawLine in ocrText.split('\n')) {
      final trimmed = rawLine.trim();
      final cleaned = trimmed.replaceAll(_edgePunct, '');
      if (cleaned.length < 3) continue;
      if (!_alnum.hasMatch(cleaned)) continue;
      if (cleaned.length <= _maxLen) return cleaned;
      return '${cleaned.substring(0, _maxLen).trimRight()}…';
    }
    return null;
  }
}
