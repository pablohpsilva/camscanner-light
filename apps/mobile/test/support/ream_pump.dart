import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/theme/ream_theme.dart';

/// Pumps [child] inside a Ream-themed MaterialApp+Scaffold for widget tests,
/// so widgets that read `context.ream` (the ReamColors extension) resolve.
Future<void> pumpReam(WidgetTester tester, Widget child, {ThemeData? theme}) {
  return tester.pumpWidget(MaterialApp(
    theme: theme ?? ReamTheme.light(),
    home: Scaffold(body: child),
  ));
}
