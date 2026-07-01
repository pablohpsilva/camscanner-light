import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I rotate the page
Future<void> iRotateThePage(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('page-viewer-rotate')));
  await tester.pumpAndSettle();
}
