// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import './../test/step/the_camera_is_ready_with_a_detector_returning_confident_corners.dart';
import './../test/step/the_live_overlay_sample_timer_fires.dart';
import './../test/step/the_live_quad_overlay_is_visible_on_the_camera_preview.dart';
import './../test/step/the_camera_is_ready_with_a_detector_returning_no_result.dart';
import './../test/step/no_live_quad_overlay_is_visible_on_the_camera_preview.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('''F3 live edge overlay in camera preview''', () {
    testWidgets('''Document detected — green outline appears''',
        (tester) async {
      await theCameraIsReadyWithADetectorReturningConfidentCorners(tester);
      await theLiveOverlaySampleTimerFires(tester);
      await theLiveQuadOverlayIsVisibleOnTheCameraPreview(tester);
    });
    testWidgets('''No document detected — no outline shown''', (tester) async {
      await theCameraIsReadyWithADetectorReturningNoResult(tester);
      await theLiveOverlaySampleTimerFires(tester);
      await noLiveQuadOverlayIsVisibleOnTheCameraPreview(tester);
    });
  });
}
