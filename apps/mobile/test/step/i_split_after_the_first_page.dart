import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I split after the first page
Future<void> iSplitAfterTheFirstPage(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('page-viewer-split')));
  await tester.pumpAndSettle();
}
