import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I delete the open document
Future<void> iDeleteTheOpenDocument(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('page-viewer-delete')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('page-viewer-delete-confirm')));
  await tester.pumpAndSettle();
}
