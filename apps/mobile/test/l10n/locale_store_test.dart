import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/l10n/locale_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('localeTag round-trips language-only and language_COUNTRY', () {
    expect(localeTag(const Locale('de')), 'de');
    expect(localeTag(const Locale('pt', 'BR')), 'pt_BR');
    expect(localeFromTag('de'), const Locale('de'));
    expect(localeFromTag('pt_BR'), const Locale('pt', 'BR'));
  });

  test('localeFromTag rejects unknown/unsupported tags', () {
    expect(localeFromTag('xx'), isNull);
    expect(localeFromTag('system'), isNull);
    expect(localeFromTag(''), isNull);
  });

  test('SharedPrefsLocaleStore round-trips an explicit locale', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SharedPrefsLocaleStore();
    await store.save(const Locale('pt', 'BR'));
    expect(await store.load(), const Locale('pt', 'BR'));
  });

  test('SharedPrefsLocaleStore stores system default as null', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SharedPrefsLocaleStore();
    await store.save(const Locale('tr'));
    await store.save(null);
    expect(await store.load(), isNull);
  });

  test('load is null when nothing stored or the tag is unsupported', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await SharedPrefsLocaleStore().load(), isNull);
    SharedPreferences.setMockInitialValues({'app_locale': 'xx_YY'});
    expect(await SharedPrefsLocaleStore().load(), isNull);
  });

  test('InMemoryLocaleStore round-trips', () async {
    final store = InMemoryLocaleStore();
    expect(await store.load(), isNull);
    await store.save(const Locale('es'));
    expect(await store.load(), const Locale('es'));
    await store.save(null);
    expect(await store.load(), isNull);
  });
}
