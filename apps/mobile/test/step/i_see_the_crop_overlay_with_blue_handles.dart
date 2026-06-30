import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/scan/widgets/crop_overlay.dart';

/// Usage: I see the crop overlay with blue handles
Future<void> iSeeTheCropOverlayWithBlueHandles(WidgetTester tester) async {
  await tester.pumpAndSettle();
  final overlay = tester.widget<CropOverlay>(find.byType(CropOverlay));
  expect(overlay.highlightColor, Colors.blue,
      reason: 'null detection result should leave handles blue (default)');
}
