import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I select the light theme
Future<void> iSelectTheLightTheme(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('segment-ThemeMode.light')));
  await tester.pumpAndSettle();
}
