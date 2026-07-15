import 'package:flutter/material.dart';
import 'package:mobile/l10n/l10n.dart';
import 'package:mobile/theme/ream_theme.dart';

/// Wraps [home] in a MaterialApp with the app's localization delegates so
/// widgets using `context.l10n` work in host tests.
Widget localizedTestApp({
  required Widget home,
  Locale locale = const Locale('en'),
}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ReamTheme.light(),
    home: home,
  );
}
