// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import './../test/step/the_app_is_launched_with_camera_permission_granted_and_empty_storage.dart';
import './../test/step/i_tap_the_scan_button.dart';
import './../test/step/i_tap_the_shutter.dart';
import './../test/step/i_tap_accept.dart';
import './../test/step/i_tap_the_sort_chip.dart';
import './../test/step/i_see_the_sort_chip_is_active.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('''Sort the library''', () {
    testWidgets('''Switch the library sort to name''', (tester) async {
      await theAppIsLaunchedWithCameraPermissionGrantedAndEmptyStorage(tester);
      await iTapTheScanButton(tester);
      await iTapTheShutter(tester);
      await iTapAccept(tester);
      await iTapTheSortChip(tester, 'name');
      await iSeeTheSortChipIsActive(tester, 'name');
    });
  });
}
