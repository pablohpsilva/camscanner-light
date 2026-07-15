import 'dart:ui';

import 'package:shared_preferences/shared_preferences.dart';

import 'locale_resolution.dart';

/// `pt_BR`-style tag used for persistence and widget keys.
String localeTag(Locale l) => l.countryCode == null
    ? l.languageCode
    : '${l.languageCode}_${l.countryCode}';

/// Inverse of [localeTag]; null for tags the app does not support (including
/// the persisted sentinel `system`), so removed languages degrade gracefully.
Locale? localeFromTag(String tag) {
  for (final supported in kSupportedAppLocales) {
    if (localeTag(supported) == tag) return supported;
  }
  return null;
}

/// Persists the user's language choice. `null` means "System default".
abstract class LocaleStore {
  Future<Locale?> load();
  Future<void> save(Locale? locale);
}

/// Production store backed by shared_preferences (key [_key]).
class SharedPrefsLocaleStore implements LocaleStore {
  static const _key = 'app_locale';

  @override
  Future<Locale?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tag = prefs.getString(_key);
      if (tag == null || tag == 'system') return null;
      return localeFromTag(tag);
    } catch (_) {
      // Store read failure -> controller falls back to System default.
      return null;
    }
  }

  @override
  Future<void> save(Locale? locale) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, locale == null ? 'system' : localeTag(locale));
  }
}

/// In-memory fake for host tests (no plugin channel).
class InMemoryLocaleStore implements LocaleStore {
  Locale? _locale;
  InMemoryLocaleStore([this._locale]);

  @override
  Future<Locale?> load() async => _locale;

  @override
  Future<void> save(Locale? locale) async => _locale = locale;
}
