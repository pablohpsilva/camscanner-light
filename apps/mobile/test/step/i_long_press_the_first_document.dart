import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I long press the first document
Future<void> iLongPressTheFirstDocument(WidgetTester tester) async {
  await tester.longPress(find.byKey(const Key('document-tile-1')));
  await tester.pumpAndSettle();
}
