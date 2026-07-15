import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _locales = [
  'en',
  'pt',
  'pt_BR',
  'es',
  'fr',
  'de',
  'lb',
  'tr',
  'ru',
  'zh',
  'ar',
];

Map<String, dynamic> _readArb(String tag) =>
    jsonDecode(File('lib/l10n/app_$tag.arb').readAsStringSync())
        as Map<String, dynamic>;

Set<String> _messageKeys(Map<String, dynamic> arb) =>
    arb.keys.where((k) => !k.startsWith('@')).toSet();

void main() {
  test('all 11 locale ARB files exist', () {
    for (final tag in _locales) {
      expect(
        File('lib/l10n/app_$tag.arb').existsSync(),
        isTrue,
        reason: 'missing lib/l10n/app_$tag.arb',
      );
    }
  });

  test('every locale has exactly the template key set', () {
    final template = _messageKeys(_readArb('en'));
    expect(template, isNotEmpty);
    for (final tag in _locales.skip(1)) {
      final keys = _messageKeys(_readArb(tag));
      expect(
        keys,
        template,
        reason:
            'app_$tag.arb key set differs from app_en.arb '
            '(missing: ${template.difference(keys)}, '
            'orphans: ${keys.difference(template)})',
      );
    }
  });

  test('every locale declares its @@locale', () {
    for (final tag in _locales) {
      expect(_readArb(tag)['@@locale'], tag);
    }
  });
}
