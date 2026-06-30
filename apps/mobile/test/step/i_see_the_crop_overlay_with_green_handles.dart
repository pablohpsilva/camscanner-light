import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/scan/widgets/crop_overlay.dart';

/// Usage: I see the crop overlay with green handles
Future<void> iSeeTheCropOverlayWithGreenHandles(WidgetTester tester) async {
  // Allow detection (async file read + FakeEdgeDetector) to complete.
  await tester.pumpAndSettle();
  final overlay = tester.widget<CropOverlay>(find.byType(CropOverlay));
  expect(overlay.highlightColor, Colors.green,
      reason: 'high-confidence detection (0.8) should produce green handles');
}
