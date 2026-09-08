import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/legal/legal_inline.dart';

/// Differential parity against the JS parser.
///
/// The app and the website render the SAME content strings through two
/// different inline parsers — `parseLegalInline` here and `parseInline` in
/// `libs/legal-content/src/inline.mjs`. `legal_inline_test.dart` mirrors the
/// JS unit fixtures, which proves the two agree on the cases someone thought
/// to write down. This proves they agree on the corpus that actually ships:
/// every unique string in all 33 documents, 11 languages, including every real
/// bold span, link, stray asterisk and RTL string.
///
/// Regenerate the fixture with:
///   node libs/legal-content/src/inline-parity-fixture.mjs
void main() {
  test('parseLegalInline matches the JS tokenisation of every shipped string', () {
    final file = File('test/features/legal/inline_parity_fixture.json');
    expect(
      file.existsSync(),
      isTrue,
      reason:
          'fixture missing — run node libs/legal-content/src/inline-parity-fixture.mjs',
    );

    final cases = jsonDecode(file.readAsStringSync()) as List;
    expect(cases, isNotEmpty);

    final mismatches = <String>[];
    for (final c in cases) {
      final input = c['input'] as String;
      final expected = (c['tokens'] as List)
          .map(
            (t) => <String, Object?>{
              'type': t['type'],
              'text': t['text'],
              if (t['url'] != null) 'url': t['url'],
            },
          )
          .toList();
      final actual = parseLegalInline(input)
          .map(
            (s) => <String, Object?>{
              'type': s.url != null ? 'link' : (s.bold ? 'bold' : 'text'),
              'text': s.text,
              if (s.url != null) 'url': s.url,
            },
          )
          .toList();
      if (jsonEncode(actual) != jsonEncode(expected)) {
        mismatches.add(
          '  input: $input\n    js  : ${jsonEncode(expected)}\n    dart: ${jsonEncode(actual)}',
        );
      }
    }

    expect(
      mismatches,
      isEmpty,
      reason:
          '${mismatches.length} of ${cases.length} strings diverged:\n'
          '${mismatches.take(5).join('\n')}',
    );
  });
}
