import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/l10n/locale_controller.dart';
import 'package:mobile/l10n/locale_store.dart';

void main() {
  test('starts from the injected initial value', () {
    final c = LocaleController(
      store: InMemoryLocaleStore(),
      initial: const Locale('fr'),
    );
    expect(c.localeOverride, const Locale('fr'));
  });

  test('load() pulls the stored value and notifies', () async {
    final c = LocaleController(store: InMemoryLocaleStore(const Locale('ru')));
    var notified = 0;
    c.addListener(() => notified++);
    await c.load();
    expect(c.localeOverride, const Locale('ru'));
    expect(notified, 1);
  });

  test(
    'load() with nothing stored stays on system and does not notify',
    () async {
      final c = LocaleController(store: InMemoryLocaleStore());
      var notified = 0;
      c.addListener(() => notified++);
      await c.load();
      expect(c.localeOverride, isNull);
      expect(notified, 0);
    },
  );

  test('setLocale notifies and persists', () async {
    final store = InMemoryLocaleStore();
    final c = LocaleController(store: store);
    var notified = 0;
    c.addListener(() => notified++);
    await c.setLocale(const Locale('ar'));
    expect(c.localeOverride, const Locale('ar'));
    expect(notified, 1);
    expect(await store.load(), const Locale('ar'));
  });

  test('setLocale(null) returns to system default and persists it', () async {
    final store = InMemoryLocaleStore(const Locale('es'));
    final c = LocaleController(store: store, initial: const Locale('es'));
    await c.setLocale(null);
    expect(c.localeOverride, isNull);
    expect(await store.load(), isNull);
  });

  test('setting the same locale again is a no-op', () async {
    final c = LocaleController(
      store: InMemoryLocaleStore(),
      initial: const Locale('de'),
    );
    var notified = 0;
    c.addListener(() => notified++);
    await c.setLocale(const Locale('de'));
    expect(notified, 0);
  });
}
