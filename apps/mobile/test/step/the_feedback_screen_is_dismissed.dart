import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/feedback/feedback_screen.dart';

/// Usage: the feedback screen is dismissed
Future<void> theFeedbackScreenIsDismissed(WidgetTester tester) async {
  expect(find.byType(FeedbackScreen), findsNothing);
}
