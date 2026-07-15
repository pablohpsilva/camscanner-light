import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/l10n/l10n.dart';
import 'package:mobile/l10n/language_autonyms.dart';
import 'package:mobile/l10n/locale_resolution.dart';
import 'package:mobile/l10n/locale_store.dart';

void main() {
  test('supported list has the 11 locales, en first', () {
    expect(kSupportedAppLocales.length, 11);
    expect(kSupportedAppLocales.first, const Locale('en'));
    expect(kSupportedAppLocales, contains(const Locale('pt', 'BR')));
    expect(kSupportedAppLocales, contains(const Locale('lb')));
  });

  test(
    'AppLocalizations.supportedLocales stays in sync with kSupportedAppLocales '
    '(guardrail: catches an ARB added without being offered/resolved, or '
    'vice versa)',
    () {
      expect(
        AppLocalizations.supportedLocales.toSet(),
        kSupportedAppLocales.toSet(),
      );
    },
  );

  test('kLanguageAutonyms stays in sync with kSupportedAppLocales '
      '(guardrail: catches an autonym-map drift)', () {
    expect(
      kLanguageAutonyms.keys.toSet(),
      kSupportedAppLocales.map(localeTag).toSet(),
    );
  });

  test('override wins over device locales', () {
    expect(
      resolveLocale([const Locale('de')], const Locale('tr')),
      const Locale('tr'),
    );
  });

  test('exact language+country match: pt-BR device -> pt_BR', () {
    expect(
      resolveLocale([const Locale('pt', 'BR')], null),
      const Locale('pt', 'BR'),
    );
  });

  test('language-only match: pt-PT device -> pt', () {
    expect(resolveLocale([const Locale('pt', 'PT')], null), const Locale('pt'));
  });

  test(
    'script/country ignored when only language matches: zh-Hant-TW -> zh',
    () {
      expect(
        resolveLocale([
          const Locale.fromSubtags(
            languageCode: 'zh',
            scriptCode: 'Hant',
            countryCode: 'TW',
          ),
        ], null),
        const Locale('zh'),
      );
    },
  );

  test('ar-EG -> ar', () {
    expect(resolveLocale([const Locale('ar', 'EG')], null), const Locale('ar'));
  });

  test('unsupported device language falls back to English', () {
    expect(resolveLocale([const Locale('ja')], null), const Locale('en'));
  });

  test('first supported locale in the device list wins', () {
    expect(
      resolveLocale([
        const Locale('ja'),
        const Locale('fr'),
        const Locale('de'),
      ], null),
      const Locale('fr'),
    );
  });

  test('null or empty device list falls back to English', () {
    expect(resolveLocale(null, null), const Locale('en'));
    expect(resolveLocale(const [], null), const Locale('en'));
  });
}
