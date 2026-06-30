import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/scan/camera_screen.dart';

import '../support/fake_library.dart';
import '../support/fake_scan.dart';

/// Usage: the app is launched with a fake detector that returns null
Future<void> theAppIsLaunchedWithAFakeDetectorThatReturnsNull(
    WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp(
    home: CameraScreen(
      dependencies: grantedScanDependenciesWithDetector(null),
      repository: FakeDocumentRepository(),
    ),
  ));
  await tester.pumpAndSettle();
}
