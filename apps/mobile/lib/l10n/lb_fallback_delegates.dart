import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// Flutter ships no Material/Cupertino/Widgets localizations for
/// Luxembourgish. These delegates accept `lb` and serve the German built-ins
/// so framework-internal strings (date pickers, tooltips, a11y labels) render
/// instead of crashing. App strings remain Luxembourgish via AppLocalizations.
const _fallback = Locale('de');

class LbMaterialLocalizationsDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const LbMaterialLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'lb';

  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      GlobalMaterialLocalizations.delegate.load(_fallback);

  @override
  bool shouldReload(LbMaterialLocalizationsDelegate old) => false;
}

class LbCupertinoLocalizationsDelegate
    extends LocalizationsDelegate<CupertinoLocalizations> {
  const LbCupertinoLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'lb';

  @override
  Future<CupertinoLocalizations> load(Locale locale) =>
      GlobalCupertinoLocalizations.delegate.load(_fallback);

  @override
  bool shouldReload(LbCupertinoLocalizationsDelegate old) => false;
}

class LbWidgetsLocalizationsDelegate
    extends LocalizationsDelegate<WidgetsLocalizations> {
  const LbWidgetsLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'lb';

  @override
  Future<WidgetsLocalizations> load(Locale locale) =>
      GlobalWidgetsLocalizations.delegate.load(_fallback);

  @override
  bool shouldReload(LbWidgetsLocalizationsDelegate old) => false;
}

const kLbFallbackDelegates = <LocalizationsDelegate<dynamic>>[
  LbMaterialLocalizationsDelegate(),
  LbCupertinoLocalizationsDelegate(),
  LbWidgetsLocalizationsDelegate(),
];
