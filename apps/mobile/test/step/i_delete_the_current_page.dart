import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I delete the current page
Future<void> iDeleteTheCurrentPage(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('page-viewer-delete-page')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('page-viewer-delete-page-confirm')));
  await tester.pumpAndSettle();
}
