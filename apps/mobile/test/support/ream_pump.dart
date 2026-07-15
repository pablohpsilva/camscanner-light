import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/l10n/l10n.dart';
import 'package:mobile/theme/ream_theme.dart';

/// Pumps [child] inside a Ream-themed MaterialApp+Scaffold for widget tests,
/// so widgets that read `context.ream` (the ReamColors extension) resolve.
/// Also wires the app's localization delegates so widgets using
/// `context.l10n` resolve.
Future<void> pumpReam(WidgetTester tester, Widget child, {ThemeData? theme}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: theme ?? ReamTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}
