import 'package:flutter_test/flutter_test.dart';

/// Usage: the live overlay sample timer fires
Future<void> theLiveOverlaySampleTimerFires(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 900));
  await tester.pump();
  await tester.pump();
}
