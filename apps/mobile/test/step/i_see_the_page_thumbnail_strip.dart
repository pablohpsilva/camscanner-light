import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I see the page thumbnail strip
Future<void> iSeeThePageThumbnailStrip(WidgetTester tester) async {
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('page-thumbnail-strip')), findsOneWidget);
  expect(find.byKey(const Key('page-thumb-0')), findsOneWidget);
  expect(find.byKey(const Key('page-thumb-1')), findsOneWidget);
}
