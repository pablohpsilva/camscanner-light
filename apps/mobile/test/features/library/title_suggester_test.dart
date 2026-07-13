import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/title_suggester.dart';

void main() {
  const s = TitleSuggester();

  test('returns null for empty/whitespace/garbage', () {
    expect(s.suggest(''), isNull);
    expect(s.suggest('   \n  \n'), isNull);
    expect(s.suggest('!!! ---'), isNull);
  });

  test('uses the first meaningful line', () {
    expect(s.suggest('INVOICE\nAcme Corp\n2026'), 'INVOICE');
  });

  test('skips short/noise leading lines', () {
    expect(s.suggest('#\nCity Water Bill\n...'), 'City Water Bill');
  });

  test('collapses internal whitespace and trims punctuation edges', () {
    expect(s.suggest('  ***  Receipt   #42  ***  '), 'Receipt   #42');
  });

  test('ellipsizes very long lines to 40 chars', () {
    final long = 'A' * 60;
    final out = s.suggest(long)!;
    expect(out.length, 41); // 40 chars + ellipsis
    expect(out.endsWith('…'), isTrue);
  });
}
