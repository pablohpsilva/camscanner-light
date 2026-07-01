import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I tap the second page thumbnail
Future<void> iTapTheSecondPageThumbnail(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('page-thumb-1')));
  await tester.pumpAndSettle();
}
