import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/l10n/locale_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

/// Fake platform implementation whose [getAll] always throws, so we can
/// prove [SharedPrefsLocaleStore.load] swallows a store read failure and
/// falls back to `null` (System default) instead of propagating.
class _ThrowingSharedPreferencesStore extends SharedPreferencesStorePlatform {
  @override
  Future<bool> clear() => throw UnsupportedError('not used by this test');

  @override
  Future<bool> clearWithParameters(ClearParameters parameters) =>
      throw UnsupportedError('not used by this test');

  @override
  Future<Map<String, Object>> getAll() =>
      throw StateError('simulated store read failure');

  @override
  Future<Map<String, Object>> getAllWithParameters(
    GetAllParameters parameters,
  ) => throw StateError('simulated store read failure');

  @override
  Future<bool> remove(String key) =>
      throw UnsupportedError('not used by this test');

  @override
  Future<bool> setValue(String valueType, String key, Object value) =>
      throw UnsupportedError('not used by this test');
}

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

  test('SharedPrefsLocaleStore.load falls back to System default (null) '
      'when the underlying store read throws', () async {
    final original = SharedPreferencesStorePlatform.instance;
    // SharedPreferences.getInstance() caches its result in a static
    // completer; reset it so this test actually reaches the (throwing)
    // platform instead of reusing a previous test's cached instance.
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = _ThrowingSharedPreferencesStore();
    addTearDown(() {
      SharedPreferencesStorePlatform.instance = original;
      SharedPreferences.resetStatic();
    });

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
