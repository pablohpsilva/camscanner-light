import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: the camera screen shows the Done button
Future<void> theCameraScreenShowsTheDoneButton(WidgetTester tester) async {
  expect(find.byKey(const Key('camera-done')), findsOneWidget,
      reason: 'Done button must be visible after first page accepted');
}
