import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/legal/legal_inline.dart';

// Mirrors libs/legal-content/test/inline.test.mjs — parseLegalInline must
// stay behaviourally identical to parseInline() in
// libs/legal-content/src/inline.mjs.
void main() {
  test('plain text is one span', () {
    final spans = parseLegalInline('hello world');
    expect(spans.length, 1);
    expect(spans.single.text, 'hello world');
    expect(spans.single.bold, isFalse);
    expect(spans.single.url, isNull);
  });

  test('bold in the middle splits into three spans', () {
    final spans = parseLegalInline('a **b** c');
    expect(spans.map((s) => s.text).toList(), ['a ', 'b', ' c']);
    expect(spans.map((s) => s.bold).toList(), [false, true, false]);
  });

  test('a link keeps its label and url', () {
    final spans = parseLegalInline('see [the policy](privacy.html) now');
    expect(spans.map((s) => s.text).toList(), ['see ', 'the policy', ' now']);
    expect(spans[1].url, 'privacy.html');
    expect(spans[0].url, isNull);
  });

  test('bold and link coexist', () {
    final spans = parseLegalInline('**Note:** mail [us](mailto:a@b.c)');
    expect(spans.map((s) => s.text).toList(), ['Note:', ' mail ', 'us']);
    expect(spans[0].bold, isTrue);
    expect(spans[2].url, 'mailto:a@b.c');
  });

  test('an unmatched asterisk pair stays literal', () {
    final spans = parseLegalInline('2 ** 3');
    expect(spans.single.text, '2 ** 3');
  });

  test('empty string yields no spans', () {
    expect(parseLegalInline(''), isEmpty);
  });

  test('stray ** does not pair with later **bold**', () {
    final spans = parseLegalInline('2 ** 3 and **real bold** end');
    expect(spans.map((s) => s.text).toList(), [
      '2 ** 3 and ',
      'real bold',
      ' end',
    ]);
    expect(spans.map((s) => s.bold).toList(), [false, true, false]);
  });

  test('adjacent bold spans stay separate', () {
    final spans = parseLegalInline('**a** and **b**');
    expect(spans.map((s) => s.text).toList(), ['a', ' and ', 'b']);
    expect(spans.map((s) => s.bold).toList(), [true, false, true]);
  });

  test('unclosed link bracket stays literal', () {
    final spans = parseLegalInline('[label](');
    expect(spans.single.text, '[label](');
    expect(spans.single.url, isNull);
  });

  test('empty link url stays literal', () {
    final spans = parseLegalInline('[label]()');
    expect(spans.single.text, '[label]()');
    expect(spans.single.url, isNull);
  });

  test('back-to-back bold spans', () {
    final spans = parseLegalInline('**a****b**');
    expect(spans.map((s) => s.text).toList(), ['a', 'b']);
    expect(spans.map((s) => s.bold).toList(), [true, true]);
  });

  test('whitespace-only bold stays literal', () {
    final spans = parseLegalInline('** **');
    expect(spans.single.text, '** **');
    expect(spans.single.bold, isFalse);
  });
}
