import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I see the camera preview
///
/// Asserts the scan-preview container is visible and the fake preview widget
/// is rendered inside it (when using FakeCameraPreviewController).
Future<void> iSeeTheCameraPreview(WidgetTester tester) async {
  expect(find.byKey(const Key('scan-preview')), findsOneWidget);
  expect(find.byKey(const Key('fake-preview')), findsOneWidget);
  expect(find.text('FAKE PREVIEW'), findsOneWidget);
}
