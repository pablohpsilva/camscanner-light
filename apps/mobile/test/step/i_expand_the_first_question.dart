import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I expand the first question
///
/// FAQ sections render as collapsed [ExpansionTile]s (question = title,
/// answer = children); tapping the first one expands it.
Future<void> iExpandTheFirstQuestion(WidgetTester tester) async {
  await tester.tap(find.byType(ExpansionTile).first);
  await tester.pumpAndSettle();
}
