import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I export the open document to PDF
Future<void> iExportTheOpenDocumentToPdf(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('page-viewer-export')));
  await tester.pumpAndSettle();
}
