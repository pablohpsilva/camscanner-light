import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the user's chosen [ThemeMode]. [load] returns null when the user
/// has never chosen — callers default to dark in that case.
abstract class ThemeModeStore {
  Future<ThemeMode?> load();
  Future<void> save(ThemeMode mode);
}

/// Production store backed by shared_preferences (key [_key]).
class SharedPrefsThemeModeStore implements ThemeModeStore {
  static const _key = 'theme_mode';

  @override
  Future<ThemeMode?> load() async {
    final prefs = await SharedPreferences.getInstance();
    switch (prefs.getString(_key)) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      default:
        return null;
    }
  }

  @override
  Future<void> save(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
  }
}

/// In-memory fake for host tests (no plugin channel).
class InMemoryThemeModeStore implements ThemeModeStore {
  ThemeMode? _mode;
  InMemoryThemeModeStore([this._mode]);

  @override
  Future<ThemeMode?> load() async => _mode;

  @override
  Future<void> save(ThemeMode mode) async => _mode = mode;
}
