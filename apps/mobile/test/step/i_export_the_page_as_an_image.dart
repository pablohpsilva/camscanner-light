import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I export the page as an image
Future<void> iExportThePageAsAnImage(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('page-viewer-export-image')));
  await tester.pumpAndSettle();
}
