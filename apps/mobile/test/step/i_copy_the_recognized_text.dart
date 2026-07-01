import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I copy the recognized text
Future<void> iCopyTheRecognizedText(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('recognized-text-copy')));
  await tester.pumpAndSettle();
}
