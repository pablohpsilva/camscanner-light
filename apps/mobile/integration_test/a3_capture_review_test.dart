// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import './../test/step/the_app_is_launched_with_camera_permission_granted.dart';
import './../test/step/i_tap_the_scan_button.dart';
import './../test/step/i_tap_the_shutter.dart';
import './../test/step/i_see_the_capture_review_screen.dart';
import './../test/step/i_tap_retake.dart';
import './../test/step/i_see_the_camera_preview.dart';
import './../test/step/i_tap_accept.dart';
import './../test/step/i_see_the_documents_home.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('''Capture a photo and review it''', () {
    testWidgets('''Tapping the shutter shows the review screen''',
        (tester) async {
      await theAppIsLaunchedWithCameraPermissionGranted(tester);
      await iTapTheScanButton(tester);
      await iTapTheShutter(tester);
      await iSeeTheCaptureReviewScreen(tester);
    });
    testWidgets('''Retake returns to the live preview''', (tester) async {
      await theAppIsLaunchedWithCameraPermissionGranted(tester);
      await iTapTheScanButton(tester);
      await iTapTheShutter(tester);
      await iTapRetake(tester);
      await iSeeTheCameraPreview(tester);
    });
    testWidgets('''Accept returns to the Documents home''', (tester) async {
      await theAppIsLaunchedWithCameraPermissionGranted(tester);
      await iTapTheScanButton(tester);
      await iTapTheShutter(tester);
      await iTapAccept(tester);
      await iSeeTheDocumentsHome(tester);
    });
  });
}
