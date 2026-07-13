import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I open the share menu
Future<void> iOpenTheShareMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('page-viewer-share')));
  await tester.pumpAndSettle();
}
