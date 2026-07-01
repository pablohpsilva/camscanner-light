import 'package:flutter_test/flutter_test.dart';

import 'the_camera_screen_is_open.dart';

/// Usage: the document has 2 pages
Future<void> theDocumentHas2Pages(WidgetTester tester) async {
  expect(h1Repo.createCalls, 1,
      reason: 'first page must create the document exactly once');
  expect(h1Repo.addPageCalls, 1,
      reason: 'second page must append exactly once via addPageToDocument');
}
