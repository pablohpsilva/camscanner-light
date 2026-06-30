// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/step/the_app_is_launched_with_a_fake_detector_that_returns_detected_corners.dart';
import './../test/step/i_tap_the_shutter.dart';
import '../test/step/i_see_the_crop_overlay_with_green_handles.dart';
import '../test/step/the_app_is_launched_with_a_fake_detector_that_returns_null.dart';
import '../test/step/i_see_the_crop_overlay_with_blue_handles.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('''Auto-fill crop corners''', () {
    testWidgets(
        '''Document detected — corners pre-filled and overlay turns green''',
        (tester) async {
      await theAppIsLaunchedWithAFakeDetectorThatReturnsDetectedCorners(tester);
      await iTapTheShutter(tester);
      await iSeeTheCropOverlayWithGreenHandles(tester);
    });
    testWidgets(
        '''No document detected — full-frame corners and blue overlay''',
        (tester) async {
      await theAppIsLaunchedWithAFakeDetectorThatReturnsNull(tester);
      await iTapTheShutter(tester);
      await iSeeTheCropOverlayWithBlueHandles(tester);
    });
  });
}
