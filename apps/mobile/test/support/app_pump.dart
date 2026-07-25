import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/l10n/l10n.dart';
import 'package:mobile/theme/app_theme.dart';

/// Pumps [child] inside a App-themed MaterialApp+Scaffold for widget tests,
/// so widgets that read `context.appColors` (the AppColors extension) resolve.
/// Also wires the app's localization delegates so widgets using
/// `context.l10n` resolve.
Future<void> pumpApp(WidgetTester tester, Widget child, {ThemeData? theme}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}
