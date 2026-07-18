// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../step/the_iap_tip_jar_on_ios.dart';
import './../step/the_platform_is_ios.dart';
import './../step/the_home_screen_is_shown.dart';
import './../step/i_see_the_donation_banner.dart';
import './../step/i_open_settings_from_home.dart';
import './../step/i_see_the_support_row.dart';
import './../step/the_platform_override_is_cleared.dart';
import './../step/the_device_has_a_bottom_safe_area_inset.dart';
import './../step/the_scan_actions_sit_clear_of_the_bottom_inset.dart';
import './../step/the_platform_is_android.dart';

void main() {
  group('''Donation entry points respect the platform''', () {
    testWidgets('''Donation entry points are shown on iOS''', (tester) async {
      await thePlatformIsIos(tester);
      await theHomeScreenIsShown(tester);
      await iSeeTheDonationBanner(tester);
      await iOpenSettingsFromHome(tester);
      await iSeeTheSupportRow(tester);
      await thePlatformOverrideIsCleared(tester);
    });
    testWidgets('''Home actions keep clear of the screen bottom on iOS''', (
      tester,
    ) async {
      await thePlatformIsIos(tester);
      await theDeviceHasABottomSafeAreaInset(tester);
      await theHomeScreenIsShown(tester);
      await theScanActionsSitClearOfTheBottomInset(tester);
      await thePlatformOverrideIsCleared(tester);
    });
    testWidgets('''Donation entry points are shown on Android''', (
      tester,
    ) async {
      await thePlatformIsAndroid(tester);
      await theHomeScreenIsShown(tester);
      await iSeeTheDonationBanner(tester);
      await iOpenSettingsFromHome(tester);
      await iSeeTheSupportRow(tester);
      await thePlatformOverrideIsCleared(tester);
    });
  });
}
