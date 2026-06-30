import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I tap the edit crop button
Future<void> iTapTheEditCropButton(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('page-viewer-edit')));
  await tester.pumpAndSettle();
}
