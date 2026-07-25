import 'package:flutter_test/flutter_test.dart';

import '../support/swipe_test_harness.dart';

/// Usage: the delete action did not fire
Future<void> theDeleteActionDidNotFire(WidgetTester tester) async {
  expect(swipeActionsFired.contains('delete'), isFalse);
}
