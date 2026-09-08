import 'package:flutter_test/flutter_test.dart';

/// Usage: the answer is shown
///
/// The FAQ's first question ("Does it work offline?") is expanded by the
/// previous step; its answer text is only mounted/visible once expanded.
Future<void> theAnswerIsShown(WidgetTester tester) async {
  expect(find.textContaining('Scanning, edge detection'), findsWidgets);
}
