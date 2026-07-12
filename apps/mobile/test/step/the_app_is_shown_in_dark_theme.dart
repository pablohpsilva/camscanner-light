import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: the app is shown in dark theme
Future<void> theAppIsShownInDarkTheme(WidgetTester tester) async {
  final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
  expect(app.themeMode, ThemeMode.dark);
}
