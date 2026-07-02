import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I share the first document
Future<void> iShareTheFirstDocument(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('document-menu-1')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('document-share-1')));
  await tester.pumpAndSettle();
}
