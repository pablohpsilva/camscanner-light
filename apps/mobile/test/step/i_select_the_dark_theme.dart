import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I select the dark theme
Future<void> iSelectTheDarkTheme(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('segment-ThemeMode.dark')));
  await tester.pumpAndSettle();
}
