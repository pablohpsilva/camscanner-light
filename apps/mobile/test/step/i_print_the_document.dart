import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I print the document
Future<void> iPrintTheDocument(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('page-viewer-share')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('page-viewer-print')));
  await tester.pumpAndSettle();
}
