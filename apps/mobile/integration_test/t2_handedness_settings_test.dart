// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import './../test/step/the_app_is_launched_with_camera_permission_granted_and_empty_storage.dart';
import './../test/step/i_open_settings_from_home.dart';
import '../test/step/i_select_lefthanded.dart';
import './../test/step/i_navigate_back_to_home.dart';
import './../test/step/the_scan_button_is_on_the_left.dart';
import '../test/step/i_select_righthanded.dart';
import './../test/step/the_scan_button_is_on_the_right.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('''Choose the scan-button handedness''', () {
    testWidgets('''Left-handed puts the Scan button on the left''',
        (tester) async {
      await theAppIsLaunchedWithCameraPermissionGrantedAndEmptyStorage(tester);
      await iOpenSettingsFromHome(tester);
      await iSelectLefthanded(tester);
      await iNavigateBackToHome(tester);
      await theScanButtonIsOnTheLeft(tester);
    });
    testWidgets('''Right-handed puts the Scan button on the right''',
        (tester) async {
      await theAppIsLaunchedWithCameraPermissionGrantedAndEmptyStorage(tester);
      await iOpenSettingsFromHome(tester);
      await iSelectRighthanded(tester);
      await iNavigateBackToHome(tester);
      await theScanButtonIsOnTheRight(tester);
    });
  });
}
