// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import './../test/step/the_app_is_launched_with_camera_permission_granted_and_empty_storage.dart';
import './../test/step/i_open_settings_from_home.dart';
import './../test/step/i_select_the_light_theme.dart';
import './../test/step/the_app_is_shown_in_light_theme.dart';
import './../test/step/i_select_the_dark_theme.dart';
import './../test/step/the_app_is_shown_in_dark_theme.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('''Choose the app theme''', () {
    testWidgets('''Switch from the default dark theme to light''', (
      tester,
    ) async {
      await theAppIsLaunchedWithCameraPermissionGrantedAndEmptyStorage(tester);
      await iOpenSettingsFromHome(tester);
      await iSelectTheLightTheme(tester);
      await theAppIsShownInLightTheme(tester);
    });
    testWidgets('''Switch to dark theme''', (tester) async {
      await theAppIsLaunchedWithCameraPermissionGrantedAndEmptyStorage(tester);
      await iOpenSettingsFromHome(tester);
      await iSelectTheDarkTheme(tester);
      await theAppIsShownInDarkTheme(tester);
    });
  });
}
