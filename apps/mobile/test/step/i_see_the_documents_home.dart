import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I see the Documents home
Future<void> iSeeTheDocumentsHome(WidgetTester tester) async {
  expect(find.widgetWithText(AppBar, 'Documents'), findsOneWidget);
  expect(find.widgetWithText(FloatingActionButton, 'Scan'), findsOneWidget);
}
