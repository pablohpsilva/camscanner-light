import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I tap the rename suggestion
Future<void> iTapTheRenameSuggestion(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('rename-suggestion')));
  await tester.pumpAndSettle();
}
