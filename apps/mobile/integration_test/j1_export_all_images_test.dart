// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import './../test/step/the_app_is_launched_with_camera_permission_granted_and_empty_storage.dart';
import './../test/step/i_tap_the_scan_button.dart';
import './../test/step/i_capture_and_accept_the_first_page.dart';
import './../test/step/i_tap_done.dart';
import './../test/step/i_open_the_first_document.dart';
import './../test/step/i_export_all_pages_as_images.dart';
import './../test/step/i_see_the_all_images_export_confirmation.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('''Export all pages as images''', () {
    testWidgets(
        '''Exporting all pages of the open document saves them as images''',
        (tester) async {
      await theAppIsLaunchedWithCameraPermissionGrantedAndEmptyStorage(tester);
      await iTapTheScanButton(tester);
      await iCaptureAndAcceptTheFirstPage(tester);
      await iTapDone(tester);
      await iOpenTheFirstDocument(tester);
      await iExportAllPagesAsImages(tester);
      await iSeeTheAllImagesExportConfirmation(tester);
    });
  });
}
