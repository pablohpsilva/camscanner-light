import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I see the capture review screen
Future<void> iSeeTheCaptureReviewScreen(WidgetTester tester) async {
  expect(find.byKey(const Key('review-image')), findsOneWidget);
  expect(find.byKey(const Key('review-retake')), findsOneWidget);
  expect(find.byKey(const Key('review-accept')), findsOneWidget);
}
