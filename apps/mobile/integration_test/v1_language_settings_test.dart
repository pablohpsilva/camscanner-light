// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import './../test/step/the_app_is_launched_with_camera_permission_granted_and_empty_persistent_storage.dart';
import './../test/step/i_open_settings_from_home.dart';
import './../test/step/i_choose_the_spanish_language.dart';
import './../test/step/the_settings_screen_is_shown_in_spanish.dart';
import './../test/step/i_navigate_back_to_home.dart';
import './../test/step/the_app_launches_reading_that_same_storage.dart';
import './../test/step/i_choose_the_system_default_language.dart';
import './../test/step/the_app_is_launched_with_camera_permission_granted_and_empty_storage.dart';
import './../test/step/i_choose_the_arabic_language.dart';
import './../test/step/the_app_is_laid_out_righttoleft.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('''Choose the app language on a device''', () {
    testWidgets('''Spanish applies immediately and survives a relaunch''', (
      tester,
    ) async {
      await theAppIsLaunchedWithCameraPermissionGrantedAndEmptyPersistentStorage(
        tester,
      );
      await iOpenSettingsFromHome(tester);
      await iChooseTheSpanishLanguage(tester);
      await theSettingsScreenIsShownInSpanish(tester);
      await iNavigateBackToHome(tester);
      await theAppLaunchesReadingThatSameStorage(tester);
      await iOpenSettingsFromHome(tester);
      await theSettingsScreenIsShownInSpanish(tester);
      await iChooseTheSystemDefaultLanguage(tester);
    });
    testWidgets('''Arabic lays the app out right-to-left''', (tester) async {
      await theAppIsLaunchedWithCameraPermissionGrantedAndEmptyStorage(tester);
      await iOpenSettingsFromHome(tester);
      await iChooseTheArabicLanguage(tester);
      await theAppIsLaidOutRighttoleft(tester);
      await iChooseTheSystemDefaultLanguage(tester);
    });
  });
}
