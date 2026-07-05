import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I tap the Fax action
Future<void> iTapTheFaxAction(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('document-1-fax')));
  await tester.pumpAndSettle();
}
