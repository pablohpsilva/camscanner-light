import 'package:flutter_test/flutter_test.dart';

import '../support/swipe_test_harness.dart';

/// Usage: the copy text action fired
Future<void> theCopyTextActionFired(WidgetTester tester) async {
  expect(swipeActionsFired, contains('copytext'));
}
