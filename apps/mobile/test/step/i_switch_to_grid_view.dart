import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I switch to grid view
Future<void> iSwitchToGridView(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('segment-grid')));
  await tester.pumpAndSettle();
}
