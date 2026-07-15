import 'package:flutter/foundation.dart';
import 'dart:ui';

import 'locale_store.dart';

/// Holds the user's language override (null = follow the device) and persists
/// changes through a [LocaleStore]. Mirrors [ThemeController].
class LocaleController extends ChangeNotifier {
  final LocaleStore _store;
  Locale? _override;

  LocaleController({required this._store, Locale? initial})
    : _override = initial;

  Locale? get localeOverride => _override;

  /// Loads the persisted choice; used when the controller is constructed
  /// synchronously (default wiring in runCamScannerApp).
  Future<void> load() async {
    final stored = await _store.load();
    if (stored == _override) return;
    _override = stored;
    notifyListeners();
  }

  Future<void> setLocale(Locale? locale) async {
    if (locale == _override) return;
    _override = locale;
    notifyListeners();
    await _store.save(locale);
  }
}
