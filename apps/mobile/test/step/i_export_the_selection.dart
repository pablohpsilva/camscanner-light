import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I export the selection
Future<void> iExportTheSelection(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('selection-export')));
  await tester.pumpAndSettle();
}
