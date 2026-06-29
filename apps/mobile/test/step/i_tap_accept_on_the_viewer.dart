import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I tap Accept on the viewer
Future<void> iTapAcceptOnTheViewer(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('edit-crop-accept')));
  await tester.pumpAndSettle();
}
