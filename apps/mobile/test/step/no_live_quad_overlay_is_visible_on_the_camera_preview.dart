import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: no live quad overlay is visible on the camera preview
Future<void> noLiveQuadOverlayIsVisibleOnTheCameraPreview(
    WidgetTester tester) async {
  expect(
    find.byKey(const Key('live-quad-overlay')),
    findsNothing,
    reason: 'LiveQuadOverlay should not be visible when no confident detection',
  );
}
