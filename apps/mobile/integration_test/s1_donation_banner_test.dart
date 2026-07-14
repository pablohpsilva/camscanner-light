// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import './../test/step/the_app_is_launched_with_camera_permission_granted_and_empty_storage.dart';
import './../test/step/the_donation_banner_matches_this_platforms_donation_availability.dart';
import './../test/step/tapping_the_donation_banner_opens_the_donation_disclaimer_where_available.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('''Donate to support the app''', () {
    testWidgets(
        '''The home banner opens the donation screen on platforms with donations''',
        (tester) async {
      await theAppIsLaunchedWithCameraPermissionGrantedAndEmptyStorage(tester);
      await theDonationBannerMatchesThisPlatformsDonationAvailability(tester);
      await tappingTheDonationBannerOpensTheDonationDisclaimerWhereAvailable(
          tester);
    });
  });
}
