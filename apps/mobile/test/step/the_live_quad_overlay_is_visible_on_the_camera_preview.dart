import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: the live quad overlay is visible on the camera preview
Future<void> theLiveQuadOverlayIsVisibleOnTheCameraPreview(
    WidgetTester tester) async {
  expect(
    find.byKey(const Key('live-quad-overlay')),
    findsOneWidget,
    reason: 'LiveQuadOverlay should be visible after confident detection',
  );
}
