import 'package:flutter/material.dart';

import 'theme_mode_store.dart';

/// Holds the active [ThemeMode] and persists changes through a [ThemeModeStore].
/// Defaults to dark when constructed without a stored value.
class ThemeController extends ChangeNotifier {
  final ThemeModeStore _store;
  ThemeMode _mode;

  ThemeController({required this._store, ThemeMode initial = ThemeMode.dark})
    : _mode = initial;

  ThemeMode get mode => _mode;

  Future<void> setMode(ThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
    await _store.save(mode);
  }
}
