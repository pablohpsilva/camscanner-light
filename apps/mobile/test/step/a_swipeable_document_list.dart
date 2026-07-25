import 'package:flutter_test/flutter_test.dart';

import '../support/swipe_test_harness.dart';

/// Usage: a swipeable document list
Future<void> aSwipeableDocumentList(WidgetTester tester) async {
  await pumpSwipeableDocumentList(tester);
}
