import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I export all pages as images
Future<void> iExportAllPagesAsImages(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('page-viewer-share')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('page-viewer-export-all-images')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('export-quality-original')));
  await tester.pumpAndSettle();
}
