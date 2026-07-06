import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I select the second document
Future<void> iSelectTheSecondDocument(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('document-tile-2')));
  await tester.pumpAndSettle();
}
