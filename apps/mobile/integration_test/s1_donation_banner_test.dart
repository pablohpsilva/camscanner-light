// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import './../test/step/the_app_is_launched_with_camera_permission_granted_and_empty_storage.dart';
import './../test/step/i_tap_the_donation_banner.dart';
import './../test/step/i_see_the_donation_disclaimer.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('''Donate to support the app''', () {
    testWidgets(
        '''Open the donation screen from the always-visible home banner''',
        (tester) async {
      await theAppIsLaunchedWithCameraPermissionGrantedAndEmptyStorage(tester);
      await iTapTheDonationBanner(tester);
      await iSeeTheDonationDisclaimer(tester);
    });
  });
}
