// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../step/the_device_language_is_brazilian_portuguese.dart';
import '../step/the_app_is_launched_with_empty_storage_and_mocked_preferences.dart';
import '../step/the_home_title_is_shown_in_brazilian_portuguese.dart';
import '../step/the_device_language_override_is_cleared.dart';
import '../step/the_device_language_is_japanese.dart';
import '../step/the_home_title_is_shown_in_english.dart';
import './../step/i_open_settings_from_home.dart';
import '../step/i_choose_the_spanish_language.dart';
import '../step/the_settings_screen_is_shown_in_spanish.dart';
import '../step/the_app_relaunches_reading_the_same_preferences.dart';
import '../step/the_home_title_is_shown_in_spanish.dart';
import '../step/the_device_language_is_german.dart';
import '../step/i_choose_the_system_default_language.dart';
import '../step/the_settings_screen_is_shown_in_german.dart';

void main() {
  group('''App language''', () {
    testWidgets('''A supported device language is used automatically''', (
      tester,
    ) async {
      await theDeviceLanguageIsBrazilianPortuguese(tester);
      await theAppIsLaunchedWithEmptyStorageAndMockedPreferences(tester);
      await theHomeTitleIsShownInBrazilianPortuguese(tester);
      await theDeviceLanguageOverrideIsCleared(tester);
    });
    testWidgets('''An unsupported device language falls back to English''', (
      tester,
    ) async {
      await theDeviceLanguageIsJapanese(tester);
      await theAppIsLaunchedWithEmptyStorageAndMockedPreferences(tester);
      await theHomeTitleIsShownInEnglish(tester);
      await theDeviceLanguageOverrideIsCleared(tester);
    });
    testWidgets('''Choosing Spanish in settings applies immediately''', (
      tester,
    ) async {
      await theAppIsLaunchedWithEmptyStorageAndMockedPreferences(tester);
      await iOpenSettingsFromHome(tester);
      await iChooseTheSpanishLanguage(tester);
      await theSettingsScreenIsShownInSpanish(tester);
      await theDeviceLanguageOverrideIsCleared(tester);
    });
    testWidgets('''The chosen language survives a relaunch''', (tester) async {
      await theAppIsLaunchedWithEmptyStorageAndMockedPreferences(tester);
      await iOpenSettingsFromHome(tester);
      await iChooseTheSpanishLanguage(tester);
      await theAppRelaunchesReadingTheSamePreferences(tester);
      await theHomeTitleIsShownInSpanish(tester);
      await theDeviceLanguageOverrideIsCleared(tester);
    });
    testWidgets('''System default returns to the device language''', (
      tester,
    ) async {
      await theDeviceLanguageIsGerman(tester);
      await theAppIsLaunchedWithEmptyStorageAndMockedPreferences(tester);
      await iOpenSettingsFromHome(tester);
      await iChooseTheSpanishLanguage(tester);
      await iChooseTheSystemDefaultLanguage(tester);
      await theSettingsScreenIsShownInGerman(tester);
      await theDeviceLanguageOverrideIsCleared(tester);
    });
  });
}
