// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import './../test/step/the_app_is_launched_with_camera_permission_denied.dart';
import './../test/step/i_tap_the_scan_button.dart';
import './../test/step/i_see_text.dart';
import './../test/step/the_app_is_launched_with_camera_permission_granted.dart';
import './../test/step/i_see_the_camera_preview.dart';
import './../test/step/the_app_is_launched_with_no_camera_available.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('''Scan camera permission and preview''', () {
    testWidgets(
        '''Permission denied shows a rationale and a path to Settings''',
        (tester) async {
      await theAppIsLaunchedWithCameraPermissionDenied(tester);
      await iTapTheScanButton(tester);
      await iSeeText(tester, 'Camera access is needed to scan documents');
      await iSeeText(tester, 'Open Settings');
    });
    testWidgets('''Permission granted shows the live preview''',
        (tester) async {
      await theAppIsLaunchedWithCameraPermissionGranted(tester);
      await iTapTheScanButton(tester);
      await iSeeTheCameraPreview(tester);
    });
    testWidgets('''No camera shows the unavailable message''', (tester) async {
      await theAppIsLaunchedWithNoCameraAvailable(tester);
      await iTapTheScanButton(tester);
      await iSeeText(tester, 'Camera unavailable on this device');
    });
  });
}
