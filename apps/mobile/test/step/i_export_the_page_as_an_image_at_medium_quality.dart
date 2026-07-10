import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I export the page as an image at Medium quality
Future<void> iExportThePageAsAnImageAtMediumQuality(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('page-viewer-share')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('page-viewer-export-image')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('export-quality-medium')));
  await tester.pumpAndSettle();
}
