import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I merge the other document
Future<void> iMergeTheOtherDocument(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('page-viewer-merge')));
  await tester.pumpAndSettle();
  // Pick the first document in the merge picker (the other document).
  await tester.tap(find.byWidgetPredicate((w) =>
      w is ListTile && w.key.toString().contains('merge-picker-item-')));
  await tester.pumpAndSettle();
}
