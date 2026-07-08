import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I open the ID scanner
///
/// Taps the Home 'Scan ID' button and pumps until the app settles. With the
/// fake sequential scanner the full front+back flow resolves immediately so
/// [pumpAndSettle] drives the app back to the home screen.
Future<void> iOpenTheIdScanner(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('home-scan-id')));
  await tester.pumpAndSettle();
}
