import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/theme/theme_mode_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SharedPrefsThemeModeStore', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('load returns null when nothing stored', () async {
      final store = SharedPrefsThemeModeStore();
      expect(await store.load(), isNull);
    });

    for (final mode in ThemeMode.values) {
      test('round-trips $mode', () async {
        final store = SharedPrefsThemeModeStore();
        await store.save(mode);
        expect(await store.load(), mode);
      });
    }

    test('load returns null for an unrecognized stored value', () async {
      SharedPreferences.setMockInitialValues({'theme_mode': 'bogus'});
      expect(await SharedPrefsThemeModeStore().load(), isNull);
    });
  });

  group('InMemoryThemeModeStore', () {
    test('defaults to the given initial then round-trips', () async {
      final store = InMemoryThemeModeStore(ThemeMode.light);
      expect(await store.load(), ThemeMode.light);
      await store.save(ThemeMode.system);
      expect(await store.load(), ThemeMode.system);
    });

    test('null initial loads null', () async {
      expect(await InMemoryThemeModeStore().load(), isNull);
    });
  });
}
