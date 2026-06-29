import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I tap the Scan button
Future<void> iTapTheScanButton(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FloatingActionButton, 'Scan'));
  await tester.pumpAndSettle();
}
