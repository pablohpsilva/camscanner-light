import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I see two page thumbnails
Future<void> iSeeTwoPageThumbnails(WidgetTester tester) async {
  await tester.pumpAndSettle();
  // The thumbnail strip renders one keyed thumbnail per page (index-based).
  // Two thumbnails ⇒ the merge produced a 2-page document. (This mirrors the
  // proven `i_see_the_page_thumbnail_strip` step's keys.)
  expect(find.byKey(const Key('page-thumbnail-strip')), findsOneWidget);
  expect(find.byKey(const Key('page-thumb-0')), findsOneWidget);
  expect(find.byKey(const Key('page-thumb-1')), findsOneWidget);
}
