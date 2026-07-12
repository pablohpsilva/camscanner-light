import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I open settings from home
Future<void> iOpenSettingsFromHome(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('home-settings')));
  await tester.pumpAndSettle();
}
